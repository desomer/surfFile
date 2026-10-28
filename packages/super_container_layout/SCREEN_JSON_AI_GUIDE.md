# Guide pour IA : Modéliser et configurer un écran en JSON (Modèle GenUI `super_container_layout`)

Ce document est la spécification technique destinée à une Intelligence Artificielle. Il décrit le format JSON plat et polymorphe inspiré de **Flutter GenUI** utilisé par `super_container_layout` pour le stockage, l'import/export et les mises à jour incrémentales (`applyVibe`).

> **Moteur d'exécution cible : Application Flutter (Material 3)**
> Ce JSON est interprété dynamiquement par une application **Flutter**. Appuie-toi sur ta connaissance de Flutter pour comprendre le comportement physique des layouts (`Flex`, `MainAxisAlignment`, `CrossAxisAlignment`, contraintes de taille, défilement `SingleChildScrollView`), l'anatomie des écrans (`Scaffold`, `AppBar`, `Drawer`, `BottomAppBar`, `TabBar` / `TabBarView`) et les conventions Material 3 (variantes de boutons `filled` / `tonal` / `elevated` / `outlined` / `text`, identifiants d'icônes Material en `snake_case`).
> **Règle stricte (zéro hallucination Flutter)** : ce format **n'est pas** un arbre de widgets Flutter sérialisé. N'invente **aucun** nom de widget ou paramètre Flutter (`Row`, `Column`, `Container`, `SizedBox`, `children`, `mainAxisSize`, `EdgeInsets`, `BoxDecoration`, etc.) qui ne figure pas dans ce guide ; utilise exclusivement le dictionnaire plat par ID (`components`, `styles`, `behaviors`) et les propriétés documentées ci-dessous.

---

## 1. Primitives et raccourcis "AI-friendly"

Le moteur JSON accepte des types concis et lisibles partout dans le document :

| Concept | Syntaxe recommandée pour l'IA | Syntaxes alternatives acceptées |
| :--- | :--- | :--- |
| **Couleurs** | Chaîne hexadécimale `"#RRGGBB"` (ex: `"#5268D9"`) ou `"#AARRGGBB"` avec transparence (ex: `"#80FFFFFF"`) | `"#RGB"`, `"#ARGB"`, `"0xAARRGGBB"` ou entier ARGB 32 bits |
| **Dimensions de slot** | `"64px"`, `"50%"`, ou nombre `64` (pixels) | `{"value": 64, "unit": "px" \| "percent"}` |
| **Tailles préférées** | `[240, 64]` ou `{"width": 240, "height": 64}` | `[null, 56]` (largeur infinie dans un composant natif) |
| **Graisse (`fontWeight`)** | `"light"`, `"normal"`, `"medium"`, `"semibold"`, `"bold"` | `100`, `200`, `300`, `400`, `500`, `600`, `700`, `800`, `900` |
| **Liaison JSON (`binding`)** | `"clients[?].nom"` (repository hérité) ou `"<repoId32Hex>:clients[?].nom"` | `{"repositoryId": "...", "path": "clients[?].nom"}` |
| **Types de placements** | `"registry:Layout"`, `"registry:Card"`, `"registry:Expansible"`, `"registry:Value"`, `"registry:Action"`, `"registry:ListView"`, `"registry:Tab"`, `"registry:IterableContent"`, `"registry:ApplicationBar"`, `"registry:BottomNavigationBar"` | `"Layout"`, `"Card"`, `"Expansible"`, `"Value"`, `"Action"`, `"Button"`, `"ListView"`, `"Tab"`, `"Tabs"`, `"AppBar"`, `"BottomBar"` |

---

## 2. Architecture GenUI : Un seul format plat par ID

Toute l'interface est représentée par des dictionnaires plats indexés par l'`id` de chaque instance :
1. **`components`** (`Map<String, ComponentConfig>`) : contient **tous** les composants, chacun identifié par son discriminateur `"type"` :
   - `"layout"` (`SuperLayoutConfig`)
   - `"native"` (`NativeComponentConfig`)
   - `"scaffold"` (`ScaffoldPageConfig`)
   - `"value"` (`SuperValueConfig`)
   - `"action"` (`SuperActionConfig`)
   - `"list"` (`SuperListViewConfig`, qui embarque directement son `"template"` de ligne)
   - `"tab"` (`SuperTabConfig`, barre d'onglets `TabBar` + vues `TabBarView` en mode statique ou dynamique)
2. **`styles`** (`Map<String, ContainerStyle>`) : contient les styles visuels des surfaces (`background`, cartes `Card`, lignes de `ListView` indexées sous `<listId>:item`, `IterableContent`).
3. **`behaviors`** (`Map<String, List<ComponentBehavior>>`) : contient les comportements déclenchés par les composants (ex. navigation `"goToPage"` sur un clic).
4. **`pageCatalog`** : catalogue des pages routées (`pages`, `homePageId`).

### Exemple complet d'écran

```json
{
  "version": 1,
  "mode": "light",
  "accent": "#5268D9",
  "styles": {
    "background": { "color": "#F5F7FA", "padding": 12 },
    "card-detail": { "color": "#FFFFFF", "radius": 16, "padding": 20, "elevation": 3 },
    "list-clients:item": { "color": "#FFFFFF", "radius": 10, "hoverEffect": true }
  },
  "behaviors": {
    "list-clients:item": [
      {
        "id": "b-view-client",
        "trigger": "click",
        "action": { "type": "goToPage", "pagePath": "/details" }
      }
    ]
  },
  "components": {
    "root": {
      "type": "native",
      "regions": { "appBar": true, "body": true },
      "placements": {
        "appBar": [{ "id": "main-appbar", "type": "registry:ApplicationBar" }],
        "body": [{ "id": "scaffold:body", "type": "scaffold:body" }]
      }
    },
    "main-appbar": {
      "type": "native",
      "regions": { "title": true },
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
      "binding": "0123456789abcdef0123456789abcdef:clients[?].nom"
    },
    "btn-save": {
      "type": "action",
      "kind": "textAndIcon",
      "variant": "filled",
      "label": "Enregistrer",
      "icon": "save"
    }
  },
  "pageCatalog": {
    "pages": [],
    "homePageId": null
  }
}
```

---

## 3. Mode "Vibe" (`applyVibe` / `surfaceUpdate` incrémental)

En mode Vibe (`AppearanceTransfer.applyVibe` ou `AppearanceCodec.patchFromJson`), tu n'as **pas besoin de renvoyer tout l'écran**. Tu envoies uniquement les clés modifiées dans `components`, `styles` ou `pageCatalog` :

1. **Modifier partiellement un composant ou un style existant** : fournis son `id` dans `components` ou `styles` avec uniquement les propriétés à changer (le champ `"type"` peut être omis si le composant existe déjà).
2. **Ajouter un composant** : déclare son entrée avec son `"type"` dans `components` et ajoute sa référence `{"id": "...", "type": "registry:..."}` dans les `placements` de son conteneur parent.
3. **Supprimer un composant** : passe son entrée à `null` dans `components` (`"components": { "old-id": null }`). Il est automatiquement supprimé de `components`, de `styles`, et retiré des `placements` de ses parents.

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
  }
}
```

---

## 4. Référence des composants du `ComponentConfigCatalog`

### 4.1. `"layout"` (`SuperLayoutConfig`)
Dispose ses enfants selon 2 modes (`"positioning"`) :
- **`"zones"` (par défaut)** : Grille 3×3 (`nw`, `north`, `ne`, `west`, `center`, `east`, `sw`, `south`, `se`).
  - `north`, `south`, `west`, `east` (`bool`) : activation des côtés.
  - `northSize`, `southSize`, `westSize`, `eastSize` (`number`, **bornes : `20` à `400`**) : épaisseur en pixels des côtés fixes.
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
    - `mainAxisAlignment` : `"start"` (défaut), `"center"`, `"end"`, `"spaceBetween"`, `"spaceAround"`, `"spaceEvenly"`.
    - `crossAxisAlignment` : `"stretch"` (défaut, occupe toute la largeur en Column / toute la hauteur en Row), `"start"`, `"center"`, `"end"`.
    - `spacing` (`number`, **bornes : `0` à `100`**, défaut `0`) : espacement en pixels entre les composants de la zone.
    - `padding` (`number`, **bornes : `0` à `200`**, défaut `0`) ou `paddingInsets` (`[top, right, bottom, left]`) : marge intérieure de la zone.
  - `resizeSides` (`bool`) et `sideResizing` (`Map<Side, bool>`) : poignées de redimensionnement utilisateur.
  - `slotSizeConstraints` (`Map<slotId, SlotSizeConstraints>`) : contraintes de taille, marges et mode d'occupation par slot enfant :
    - `minWidth`, `minHeight`, `preferredWidth`, `preferredHeight`, `maxWidth`, `maxHeight` : dimensions en `"px"` ou `"%"` (ex: `"240px"`, `"50%"`).
    - `percentBasis` : `"zone"` (défaut) ou `"layout"`.
    - `padding` (`0`..`200`) ou `paddingInsets` (`[top, right, bottom, left]`).
    - `fitContent` (`bool?`, ou alias `"flex": 0 | 1`) : surcharge par slot l'occupation sur l'axe principal :
      - `true` (ou `"flex": 0`) : le slot prend uniquement la taille de son contenu (ne s'étire pas).
      - `false` (ou `"flex": 1`) : le slot s'étire pour remplir l'espace restant de la zone (même si la zone a `expandSlots: false`).
      - `null` (omis) : suit le comportement de la zone (`zoneFlows[zone].expandSlots`).
  - **Bonne pratique (empilement de `Card`, boutons ou champs sans occuper toute la hauteur)** :
    - Par défaut dans `center`, les composants sans `preferredHeight` se partagent toute la hauteur (`expandSlots: true`). Pour empiler des cartes (`Card`) ou contrôles qui s'adaptent à la hauteur de leur contenu, configure `zoneFlows.center` avec `"expandSlots": false` (et `"scrollable": true` si la liste de composants peut dépasser l'écran), ou mets `"fitContent": true` sur les slots concernés dans `slotSizeConstraints`.
    - **À éviter** : ne mets pas `"fitContent": true` sur `"scaffold:body"` dans `"root"`, car `"scaffold:body"` est le conteneur de la page entière ; configure `zoneFlows` ou `slotSizeConstraints` dans `"mainLayout"` (ou le layout de la page).
  - `slotLabels` (`Map<slotId, string>`) : libellés personnalisés des slots.
  - `placements` (`Map<Zone, List<{"id": string, "type": string}>>`) : composants placés dans chaque zone.
- **`"grid"`** : Grille libre 2D (`columns` de `1` à `48`, `rowHeight` de `16` à `400`, `gap` de `0` à `64`).

### 4.2. `"native"` (`NativeComponentConfig`) & `"scaffold"` (`ScaffoldPageConfig`) — Lien avec les widgets Flutter Material
Les composants `"native"` et `"scaffold"` sont des adaptateurs directs vers les widgets structurels standards de la bibliothèque **Flutter Material** (`package:flutter/material.dart`). Leurs noms de régions dans `regions` et `placements` reprennent exactement les paramètres nommés des constructeurs Flutter correspondants :

- **Page / Écran (`"root"` ou `<pageId>` du `pageCatalog`) $\rightarrow$ `Scaffold` de Flutter** (`type: "native"` ou `"scaffold"`) :
  - `appBar` (1 slot max, dédié au composant `"registry:ApplicationBar"`) : barre supérieure du `Scaffold`.
  - `body` (empilement vertical, toujours actif) : contenu principal de la page. Pour `"root"`, contient par défaut `{"id": "scaffold:body", "type": "scaffold:body"}` qui monte le layout `"mainLayout"`.
  - `drawer` / `endDrawer` (empilement vertical) : panneaux latéraux coulissants gauche / droite (`Drawer` Flutter).
  - `bottomNavigationBar` (1 slot max, dédié au composant `"registry:BottomNavigationBar"`) : barre de navigation inférieure.
  - `floatingActionButton` (1 slot max) : bouton d'action flottant en bas à droite.
  - `bottomSheet` (1 slot max) : panneau persistant affiché en bas du `Scaffold`.

- **`"registry:ApplicationBar"` $\rightarrow$ `AppBar` de Flutter** (`type: "native"`, uniquement plaçable dans la région `appBar` d'une page) :
  - `useDefaultNavigation` (`bool`, `true` par défaut) : laisse Flutter gérer automatiquement le bouton menu (`Drawer`) ou retour (`BackButton`). Mettre à `false` pour utiliser une région `leading` personnalisée.
  - **Régions** :
    - `leading` (1 slot max) : widget placé tout à gauche de l'`AppBar` (ignoré si `useDefaultNavigation: true`).
    - `title` (liste horizontale) : titre ou barre d'outils centrale de l'`AppBar`.
    - `actions` (liste horizontale) : boutons/actions alignés à droite de l'`AppBar`.
    - `bottom` (1 slot max) : barre secondaire sous l'`AppBar` (ex. onglets ou barre de filtres).
    - `flexibleSpace` (1 slot max) : arrière-plan de l'`AppBar`.
  - **Propriétés de style Flutter `AppBar` (directement à la racine de `components[appBarId]`)** :
    - Couleurs (`"#RRGGBB"` ou `"#AARRGGBB"`) : `backgroundColor`, `foregroundColor`, `surfaceTintColor`, `shadowColor`.
    - Élévation & transparence : `elevation` (`0`..`24`), `scrolledUnderElevation` (`0`..`24`), `forceMaterialTransparency` (`bool`, défaut `false`).
    - Forme et bordure (`shape`) : objet `{"kind": "rounded" | "continuous" | "beveled" | "stadium" | "linear", "radius": 0..64, "radii": [topLeft, topRight, bottomRight, bottomLeft], "borderWidth": 0..16, "borderColor": "#RRGGBB", "top": bool, "right": bool, "bottom": bool, "left": bool}` (ou raccourcis : nombre `16` pour un rayon uniforme, ou `[0, 0, 16, 16]` pour des coins indépendants).
    - Dimensions & espacements : `toolbarHeight` (`32`..`160`, défaut `56`), `leadingWidth` (`24`..`200`, défaut `56`), `titleSpacing` (`0`..`64`, défaut `0`).
    - Comportement & opacité : `centerTitle` (`bool`), `toolbarOpacity` (`0.0`..`1.0`, défaut `1.0`), `bottomOpacity` (`0.0`..`1.0`, défaut `1.0`), `primary` (`bool`, défaut `true`), `excludeHeaderSemantics` (`bool`, défaut `false`), `clipBehavior` (`"none"` | `"hardEdge"` | `"antiAlias"` | `"antiAliasWithSaveLayer"`), `systemOverlayStyle` (`"light"` | `"dark"`).
    - Pour réinitialiser une propriété au thème Material 3 par défaut en mode Vibe (`applyVibe`), passe sa valeur à `null` (ex. `{"backgroundColor": null}`).

- **`"registry:BottomNavigationBar"` $\rightarrow$ `BottomAppBar` de Flutter** (`type: "native"`, uniquement plaçable dans la région `bottomNavigationBar` d'une page) :
  - `left` (liste horizontale, alignée à gauche), `center` (liste horizontale, centrée), `right` (liste horizontale, alignée à droite).

- **`"registry:Card"` $\rightarrow$ Conteneur monoenfant (`Card` / `Container` Flutter) + surface `ContainerStyle` enrichie** (`type: "native"` + entrée associée sous le même `id` dans `styles`) :
  - `child` (1 slot unique max, région obligatoire toujours active) : comme un `Card` ou `Container` Flutter, ne prend qu'un seul composant enfant `child` (souvent un `"registry:Layout"` pour organiser plusieurs sous-composants, ou utilise `"registry:IterableContent"` si tu veux fusionner carte et grille sous le même ID).
  - **Carte vide / purement visuelle (ex. affiche, miniature, séparateur ou bloc avec `fill.imageUrl`)** : si une `Card` ne contient aucun composant enfant, **ne mets jamais `"regions": { "child": false }`** (la région `child` d'une `Card` est requise et ne peut pas être désactivée). Utilise `"regions": {}, "placements": {}` (ou `"regions": { "child": true }, "placements": {}`), ou omet simplement l'entrée de `components["<cardId>"]` et définis uniquement son style dans `styles["<cardId>"]`.
  - **Style visuel de la carte (bien plus riche qu'un `Card` Flutter natif)** : se configure intégralement dans **`styles["<cardId>"]`** (système de design Material / Neumorphism / Liquid Glass, couleur unie, dégradés `linear` / `radial` / `sweep`, image de fond, coins uniformes ou par angle, bordures pleines / tiretées / pointillées par côté, ombre portée ou intérieure, halo néon, flou `backdropBlur`, motif `grain` / `lines` / `dots`, transformation 2D, effets de clic/survol et états `states` — voir § 4.7).

- **`"registry:Expansible"` $\rightarrow$ `Expansible` de Flutter** (`type: "native"`) :
  - `header` (liste horizontale) : en-tête toujours visible. Un clic sur `header` bascule l'état ouvert/fermé lorsque `headerClickToggles` vaut `true` (défaut).
  - `body` (liste verticale) : contenu dépliable animé.
  - Options propres à `Expansible` dans `components[id]` (`type: "native"`) : `initiallyExpanded` (`bool`, défaut `false`), `maintainState` (`bool`, défaut `true`), `headerClickToggles` (`bool`, défaut `true`), `binding` (`"clients[?].ouvert"` ou `{"repositoryId": "...", "path": "..."}` — liaison bidirectionnelle vers un attribut booléen JSON).

- **`"registry:IterableContent"` $\rightarrow$ Surface stylisée + `SuperLayout` intégré (alternative compacte à `Card` + `Layout`)** :
  - Contrairement à `Card` (qui n'accepte qu'un seul `child` dans une config `"native"` et nécessite un second composant `"layout"` enfant), `IterableContent` fusionne directement **une surface stylisée** (`styles[id]`) et **une grille `SuperLayout`** (`components[id]` avec `"type": "layout"`) sous **le même `id`** !
  - De plus, `IterableContent` fournit automatiquement un `ContentHoverScope` à tous ses composants enfants, ce qui permet aux `Value`, `Action` et `styles` placés à l'intérieur de réagir à l'état automatique `contentHover` dès que le curseur survole la carte.

Propriétés communes dans `components[id]` pour `"native"` : `useDefaultNavigation` (`bool?`), `regions` (`Map<string, bool>`), `placements` (`Map<string, List<{"id": string, "type": string}>>`), `slotPreferredSizes`, `slotSizeConstraints`, `slotLabels`.

### 4.3. `"value"` (`SuperValueConfig`)
Affiche un texte, un champ de saisie, une case à cocher ou un interrupteur :
- `mode` : `"display"` (défaut) ou `"input"`.
- `kind` : `"text"` (défaut), `"checkbox"` ou `"switch"` (`"switchControl"`).
- `text` (ou `initialText`) : texte initial (`string`).
- `value` (ou `initialBool`) : valeur booléenne initiale (`bool`) pour `checkbox` / `switch`.
- `label`, `placeholder` : `string`.
- `enabled` (`true`), `readOnly` (`false`), `obscureText` (`false`) : `bool`.
- `minLines` (`1`), `maxLines` (`1`) : `int` (`maxLines >= minLines >= 1`).
- Typographie : `fontFamily` (`string`), `fontSize` (`number > 0`), `fontWeight` (`"light"`, `"normal"`, `"medium"`, `"semibold"`, `"bold"` ou `100`..`900`), `italic` (`bool`), `color` (`"#RRGGBB"`), `textAlign` (`"start"`, `"center"`, `"end"`, `"left"`, `"right"`, `"justify"`), `lineHeight` (`number > 0`), `letterSpacing` (`number`).
- `binding` : `"clients[?].nom"` ou `{"repositoryId": "...", "path": "..."}`.
- `field` (`SuperTextFieldConfig`, pour `mode: "input"`).
- `propertyBindings` & `states` : liaisons repository et surcharges par état (voir § 4.8).

### 4.4. `"action"` (`SuperActionConfig`)
Affiche un bouton interactif :
- `kind` : `"text"` (défaut), `"icon"`, ou `"textAndIcon"`.
- `variant` : `"filled"` (défaut), `"tonal"`, `"elevated"`, `"outlined"`, `"text"`, `"icon"`, ou `"surface"`.
- `label` (ou `text`) : libellé du bouton (`string`, défaut `"Action"`).
- `tooltip` : infobulle (`string`).
- `icon` : identifiant d'icône du catalogue `MaterialIconCatalog` (ex. `"touch_app"`, `"smart_button"`, `"add"`, `"add_circle"`, `"remove"`, `"edit"`, `"delete"`, `"check"`, `"check_circle"`, `"close"`, `"search"`, `"settings"`, `"tune"`, `"refresh"`, `"autorenew"`, `"save"`, `"share"`, `"download"`, `"upload"`, `"send"`, `"copy"`, `"paste"`, `"cut"`, `"undo"`, `"redo"`, `"filter_list"`, `"sort"`, `"print"`, `"qr_code"`, `"auto_awesome"`, `"build"`, `"home"`, `"arrow_back"`, `"arrow_forward"`, `"arrow_upward"`, `"arrow_downward"`, `"chevron_left"`, `"chevron_right"`, `"expand_more"`, `"expand_less"`, `"menu"`, `"more_vert"`, `"more_horiz"`, `"open_in_new"`, `"fullscreen"`, `"dashboard"`, `"apps"`, `"location_on"`, `"map"`, `"language"`, `"email"`, `"phone"`, `"chat"`, `"forum"`, `"notifications"`, `"alternate_email"`, `"folder"`, `"folder_open"`, `"create_new_folder"`, `"description"`, `"insert_drive_file"`, `"attach_file"`, `"link"`, `"calendar"`, `"schedule"`, `"bookmark"`, `"label"`, `"list"`, `"grid_view"`, `"table_chart"`, `"code"`, `"terminal"`, `"storage"`, `"cloud"`, `"cloud_upload"`, `"cloud_download"`, `"archive"`, `"play_arrow"`, `"pause"`, `"stop"`, `"skip_next"`, `"skip_previous"`, `"volume_up"`, `"volume_off"`, `"mic"`, `"image"`, `"photo_camera"`, `"videocam"`, `"music_note"`, `"palette"`, `"info"`, `"help"`, `"warning"`, `"error"`, `"favorite"`, `"star"`, `"thumb_up"`, `"bolt"`, `"lightbulb"`, `"flag"`, `"verified"`, `"person"`, `"person_add"`, `"group"`, `"account_circle"`, `"badge"`, `"visibility"`, `"visibility_off"`, `"lock"`, `"lock_open"`, `"key"`, `"shield"`, `"login"`, `"logout"`, `"shopping_cart"`, `"shopping_bag"`, `"credit_card"`, `"payments"`, `"receipt"`, `"savings"`, `"analytics"`, `"trending_up"`, `"pie_chart"`, `"work"`, `"inventory"`, `"local_shipping"`).
- `iconPosition` : `"leading"` (défaut) ou `"trailing"`.
- `iconSize` (`number > 0`), `iconSpacing` (`number >= 0`, défaut `8`).
- `enabled` (`bool`, défaut `true`).
- Typographie & Couleurs : `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `iconColor`, `backgroundColor`, `borderColor`, `radius`, `borderWidth`, `elevation`, `horizontalPadding`, `verticalPadding`, `textAlign`, `letterSpacing`.
- `style` (`ContainerStyle`) : style de surface avancé optionnel.
- `propertyBindings` & `states` : liaisons repository et états nommés/automatiques (voir § 4.8).

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
- Propriétés de `components[listId]` (`type: "list"`) :
  - `binding` : `"clients"` (si imbriquée) ou `{"repositoryId": "<32hex>", "path": "clients"}`.
  - `axis` : `"vertical"` (défaut) ou `"horizontal"`.
  - `wrap` : `bool` (`false` par défaut ; si `true`, disposition fluide en grille `Wrap`).
  - `wrapSizing` : `"fixed"` ou `"automatic"`.
  - `itemWidth` (`160`), `itemExtent` (`56`) : `number` entre **`16` et `2000`**.
  - `spacing` (`0`) : `number` entre **`0` et `200`**.
  - `allowAdd` (`false`), `allowRemove` (`false`) : `bool` (génère automatiquement le bouton `+` d'ajout et l'icône de suppression sur chaque ligne : inutile de créer des boutons `Action` manuels pour ajouter/supprimer une ligne).
  - `emptyText` : `string` (`"Aucun élément"`).
  - `template` (alias `"row"`) : `SuperLayoutConfig` embarqué décrivant la disposition des lignes.
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
    - `slotPreferredSizes`, `slotSizeConstraints`, `slotLabels`.

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
      "binding": "0123456789abcdef0123456789abcdef:categories",
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
        "label": "0123456789abcdef0123456789abcdef:categories[?].nom"
      }
    },
    "tpl-tab-detail": {
      "type": "value",
      "mode": "display",
      "binding": "0123456789abcdef0123456789abcdef:categories[?].description"
    }
  }
}
```

### 4.7. Toutes les capacités de style des Cartes (`Card` / surfaces) et du Fond (`background` & fenêtre)

Le dictionnaire `styles` (`Map<String, ContainerStyle>`) contrôle l'apparence visuelle de toutes les surfaces de l'application :
- **`styles["background"]`** : le fond global de l'application/écran.
- **`styles["<cardId>"]`** : chaque composant `"registry:Card"` ou `"registry:IterableContent"`.
- **`styles["<listId>:item"]`** (ou `styles["<listId>"]`) : la carte de chaque ligne d'une `ListView`.
- **`components["<tabId>"].tabBarStyle`** et **`components["<actionId>"].style`** : utilisent exactement le même objet `ContainerStyle`.

---

#### 4.7.1. Style du Fond de l'écran (`styles["background"]`) et de la Fenêtre (propriétés racines)

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
     - Image d'arrière-plan via `fill.imageUrl` (`https://...`), `fill.imageFit` et `fill.imageOpacity`.
   - **Cadre et lueur périphériques de l'écran** :
     - `borderWidth` (**`0` à `4`**) et `borderColor` (`"#RRGGBB"`) : dessine une bordure autour de toute la zone de l'application.
     - `neon` (`true` ou `{"enabled": true, "color": "#00FFFF", "intensity": 0..3}`) : ajoute un halo néon autour de l'écran.
   - **Marges globales de l'écran (`padding` / `paddingInsets`, `margin` / `marginInsets`)** :
     - `padding` (**`0` à `48`**) ou `paddingInsets` (`[top, right, bottom, left]` de **`0` à `48`**) : espace intérieur global autour de la page principale.
     - `margin` (**`0` à `48`**) ou `marginInsets` (`[top, right, bottom, left]` de **`0` à `48`**).

---

#### 4.7.2. Toutes les capacités de style d'une Carte (`Card`, `IterableContent`, surfaces) dans `ContainerStyle`

Chaque carte (`styles["<cardId>"]`) ou surface dispose des 8 familles de réglages suivantes :

1. **Système de design (`designSystem`)** :
   - `"material"` (défaut) : surface plane Material avec ombre portée classique.
   - `"neumorphism"` : relief doux en extrusion avec double ombre portée (claire en haut-gauche, sombre en bas-droite) calculée dynamiquement à partir de la couleur `color` de la carte, de `elevation` (distance du relief) et de `shadowOpacity` (force du relief).
   - `"liquidGlass"` : effet verre liquide translucide appliquant automatiquement un flou d'arrière-plan (`BackdropFilter` de `20px` par défaut, surchargeable via `backdropBlur`), un dégradé diagonal translucide et un contour lumineux.

2. **Remplissage : Couleur unie, Dégradés et Image de fond (`color` & `fill`)** :
   - `color` : `"#RRGGBB"` ou `"#AARRGGBB"` — couleur unie de la carte lorsque `fill.type` vaut `"solid"` (le texte interne ajuste automatiquement son contraste clair/sombre sauf en `liquidGlass`).
   - `fill` (`ContainerFill`) :
     - `type` :
       - `"solid"` (défaut) : utilise la couleur unie `color`.
       - `"linear"` : dégradé linéaire de `start` vers `end` orienté selon `angle`.
       - `"radial"` : dégradé circulaire du centre (`start`) vers l'extérieur (`end`) de rayon `radius`.
       - `"sweep"` : dégradé conique/balayage autour du centre avec rotation `angle`.
     - `start` : `"#RRGGBB"` ou `"#AARRGGBB"` (défaut `"#5268D9"`).
     - `end` : `"#RRGGBB"` ou `"#AARRGGBB"` (défaut `"#B794F4"`).
     - `angle` : nombre de **`0` à `360`** degrés (`45` par défaut ; utilisé par `"linear"` et `"sweep"`).
     - `radius` : nombre de **`0.1` à `2.0`** (`0.8` par défaut ; utilisé par `"radial"`).
     - `imageUrl` : `string` (`"https://..."`) — affiche une image réseau en fond de la carte (peut se superposer à `color` ou au dégradé).
     - `imageFit` : `"cover"` (défaut), `"contain"`, `"fill"`, `"fitWidth"`, `"fitHeight"`, `"none"`, `"scaleDown"`.
     - `imageOpacity` : nombre de **`0.0` à `1.0`** (`1.0` par défaut).

3. **Coins et arrondis (`radius` & `radii`)** :
   - `radius` : nombre de **`0` à `36`** (`0` par défaut) — rayon d'arrondi uniforme des 4 coins.
   - `radii` : `[topLeft, topRight, bottomRight, bottomLeft]` où chaque valeur est entre **`0` à `36`** — rayons asymétriques coin par coin (prioritaire sur `radius`).

4. **Bordures (`borderWidth`, `borderWidths`, `borderColor`, `borderLine`)** :
   - `borderWidth` : nombre de **`0` à `4`** (`0` par défaut, aucune bordure) — épaisseur uniforme.
   - `borderWidths` : `[top, right, bottom, left]` où chaque valeur est entre **`0` à `4`** — épaisseur indépendante par côté (ex: `[0, 0, 0, 4]` pour une barre d'accentuation uniquement à gauche).
   - `borderColor` : `"#RRGGBB"` ou `"#AARRGGBB"`.
   - `borderLine` : style du trait : `"solid"` (plein, défaut), `"dashed"` (tireté), `"dotted"` (pointillé).

5. **Ombres portées, Ombre intérieure en creux et Halo Néon (`elevation`, `shadowOpacity`, `shadow`, `innerShadow`, `neon`)** :
   - `elevation` : nombre de **`0` à `16`** (`0` par défaut) — hauteur d'ombre portée standard (ou distance du relief en `"neumorphism"`).
   - `shadowOpacity` : nombre de **`0.0` à `1.0`** (`0.2` par défaut) — intensité de l'ombre liée à `elevation`.
   - `shadow` (`ShadowSpec`, optionnel) : ombre portée personnalisée (remplace l'ombre automatique d'`elevation`) :
     ```json
     { "enabled": true, "color": "#000000", "opacity": 0.15, "blur": 24, "spread": -4, "dx": 0, "dy": 10 }
     ```
     Bornes : `enabled` (`bool`, défaut `true`), `color` (`"#RRGGBB"`, défaut `"#000000"`), `opacity` (**`0` à `1`**, défaut `0.1`), `blur` (**`0` à `48`**, défaut `16`), `spread` (**`-32` à `32`**, défaut `0`), `dx` (**`-32` à `32`**, défaut `0`), `dy` (**`-32` à `32`**, défaut `8`).
   - `innerShadow` (`ShadowSpec`, optionnel) : ombre intérieure dessinée à l'intérieur des bords de la carte (effet enfoncé / creusé). Accepte exactement les mêmes champs et bornes que `shadow`.
   - `neon` (`NeonStyle`, optionnel) : halo lumineux diffus autour de la carte :
     - Booléen `true` (active avec intensité `0.6` et la couleur `accent`), ou objet `{"enabled": true, "color": "#00FFFF", "intensity": 1.2}`.
     - Bornes de `intensity` : **`0.0` à `3.0`** (`0.6` par défaut).

6. **Espacements intérieur et extérieur (`padding`, `paddingInsets`, `margin`, `marginInsets`)** :
   - `padding` : **`0` à `48`** (`0` par défaut) — marge intérieure uniforme entre la bordure de la carte et son widget enfant.
   - `paddingInsets` : `[top, right, bottom, left]` de **`0` à `48`** — marge intérieure par côté (prioritaire sur `padding`).
   - `margin` : **`0` à `48`** (`0` par défaut) — marge extérieure uniforme autour de la carte.
   - `marginInsets` : `[top, right, bottom, left]` de **`0` à `48`** — marge extérieure par côté (prioritaire sur `margin`).

7. **Texture, Flou d'arrière-plan, Opacité et Transformation 2D (`opacity`, `backdropBlur`, `pattern`, `patternOpacity`, `transform`)** :
   - `opacity` : **`0.0` à `1.0`** (`1.0` par défaut) — transparence globale de la carte et de ses enfants.
   - `backdropBlur` : **`0` à `40`** — flou gaussien de ce qui se trouve derrière la carte (associe-le à une `color` ou un `fill` semi-transparent `#AARRGGBB` pour un effet verre dépoli).
   - `pattern` : motif décoratif superposé au fond de la carte : `"none"` (défaut), `"grain"` (texture bruitée), `"lines"` (hachures diagonales), `"dots"` (trame de points).
   - `patternOpacity` : **`0.0` à `1.0`** (`0.1` par défaut) — opacité du motif `pattern`.
   - `transform` : transformation géométrique 2D centrée sur la carte :
     - `dx` (**`-48` à `48`**, défaut `0`), `dy` (**`-48` à `48`**, défaut `0`), `rotation` (**`-180` à `180`** degrés, défaut `0`), `scale` (**`0.5` à `1.5`**, défaut `1.0`).

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
      "padding": 16
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

### 4.8. États interactifs et styles conditionnels (`states`)

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
| Value | `content` (`mode`, `kind`, `initialText`, `initialBool`, `obscureText`, `minLines`, `maxLines`, `field`), `textLabel` (`label`), `placeholder`, `enabled` (`enabled` + `readOnly`), `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `textAlign`, `lineHeight`, `letterSpacing`, `binding` |
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
    "binding": "0123456789abcdef0123456789abcdef:clients[?].statut",
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

### 4.9. Comportements (`behaviors`) : Actions et navigation au clic

Le dictionnaire `behaviors` (`Map<String, List<ComponentBehavior>>`) associe des comportements interactifs à n'importe quel composant par son ID technique :
- **Déclencheurs (`trigger`)** :
  - `"click"` : Déclenché lors d'un clic (ou tap) sur le composant lorsque le mode édition est désactivé. Le curseur passe automatiquement en pointeur (`click`).
- **Actions polymorphes (`action`)** :
  - `"goToPage"` (`GoToPageAction`) : Navigation vers une page ou une URL.
    - `pagePath` : Chemin absolu vers lequel naviguer (ex. `"/details"`, `"/clients"`).
    - `pageId` (optionnel) : Identifiant de la page dans `pageCatalog` (ex. `"page-detail"`).
    - `pageName` (optionnel) : Nom lisible de la page cible (ex. `"Détails"`).

#### Exemple : Action de navigation sur un bouton ou sur une ligne de liste

```json
{
  "behaviors": {
    "btn-home": [
      {
        "id": "b-home",
        "trigger": "click",
        "action": {
          "type": "goToPage",
          "pagePath": "/home",
          "pageName": "Accueil"
        }
      }
    ],
    "list-clients:item": [
      {
        "id": "b-client-details",
        "trigger": "click",
        "action": {
          "type": "goToPage",
          "pagePath": "/clients/details",
          "pageName": "Fiche Client"
        }
      }
    ]
  }
}
```

---

## 5. Composants implicites déjà fournis par défaut (À ne JAMAIS dupliquer)

Certains widgets structurels sont instanciés automatiquement par le framework. Tu dois les **configurer** plutôt que d'en ajouter de nouveaux par-dessus :

| Contexte | Ce qui est déjà fourni par défaut | Comment le configurer (sans le recréer) |
| :--- | :--- | :--- |
| **Page principale (`"root"`)** | Sa région `body` contient déjà `{"id": "scaffold:body", "type": "scaffold:body"}` qui monte un `SuperLayout` d'ID **`"mainLayout"`**, et le fond de page utilise **`styles["background"]`**. | Modifie directement `components["mainLayout"]` (`type: "layout"`) et `styles["background"]`. Ne remplace pas `"scaffold:body"` par un autre Layout. |
| **Chaque ligne d'une `ListView` (`<listId>`)** | Chaque ligne est déjà un **`IterableContent`** d'ID **`<listId>:item`** (surface stylisée + `SuperLayout` d'ID **`<listId>:layout`** + `ContentHoverScope`), plus les boutons natifs d'ajout (`allowAdd`) et de suppression (`allowRemove`). | Configure la grille de la ligne dans `components["<listId>"].template`, le style de la carte de ligne dans `styles["<listId>:item"]` (ou `styles["<listId>"]`), et les comportements au clic de la ligne dans `behaviors["<listId>:item"]`. N'enveloppe pas la ligne dans un `Card` ou un `IterableContent` supplémentaire. |
| **Barre d'onglets d'un `SuperTab` (`<tabId>`)** | La `TabBar` est déjà enveloppée dans une surface stylisable via `components["<tabId>"].tabBarStyle`, et en mode `"dynamic"`, les boutons `+` (`allowAdd`) et `×` (`allowRemove`) sont générés nativement. | Configure directement `tabBarStyle` dans `components["<tabId>"]` et active `allowAdd` / `allowRemove` en mode `"dynamic"` sans créer de boutons d'ajout/suppression supplémentaires. |
| **`ApplicationBar`** | Tant que `useDefaultNavigation` vaut `true` (défaut), Flutter affiche automatiquement le bouton menu (`Drawer`) ou retour (`BackButton`) à gauche, ainsi que les boutons système à droite. | N'ajoute pas de bouton menu/retour dans `leading` sauf si tu passes explicitement `"useDefaultNavigation": false`. |

---

## 6. Chat Vibe du mode édition

La bannière du mode édition ouvre un chat flottant et déplaçable. Chaque demande envoie à Gemini la conversation et l’export JSON courant de l’apparence. La réponse est appliquée avec `AppearanceTransfer.applyVibe` ; elle doit suivre la forme `{"message":"résumé","vibe":{"components":{...},"styles":{...}}}`.

Pour l’application de démonstration, la clé `GEMINI_API_KEY` peut être définie dans le fichier local `env` ou dans l’environnement du processus. Ne versionnez jamais cette clé. Les applications de production devraient appeler un service intermédiaire plutôt que d’embarquer une clé Gemini dans le client.
