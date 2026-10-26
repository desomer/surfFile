# Guide pour IA : Modéliser et configurer un écran en JSON (Modèle GenUI `super_container_layout`)

Ce document est la spécification technique destinée à une Intelligence Artificielle. Il décrit le format JSON plat et polymorphe inspiré de **Flutter GenUI** utilisé par `super_container_layout` pour le stockage, l'import/export et les mises à jour incrémentales (`applyVibe`).

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
| **Types de placements** | `"registry:Layout"`, `"registry:Card"`, `"registry:Expansible"`, `"registry:Value"`, `"registry:Action"`, `"registry:ListView"`, `"registry:IterableContent"`, `"registry:ApplicationBar"`, `"registry:BottomNavigationBar"` | `"Layout"`, `"Card"`, `"Expansible"`, `"Value"`, `"Action"`, `"Button"`, `"ListView"`, `"AppBar"`, `"BottomBar"` |

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
  - `leading` (1 slot max) : widget placé tout à gauche de l'`AppBar` (ignoré si `useDefaultNavigation: true`).
  - `title` (liste horizontale) : titre ou barre d'outils centrale de l'`AppBar`.
  - `actions` (liste horizontale) : boutons/actions alignés à droite de l'`AppBar`.
  - `bottom` (1 slot max) : barre secondaire sous l'`AppBar` (ex. onglets ou barre de filtres).
  - `flexibleSpace` (1 slot max) : arrière-plan de l'`AppBar`.
- **`"registry:BottomNavigationBar"` $\rightarrow$ `BottomAppBar` de Flutter** (`type: "native"`, uniquement plaçable dans la région `bottomNavigationBar` d'une page) :
  - `left` (liste horizontale, alignée à gauche), `center` (liste horizontale, centrée), `right` (liste horizontale, alignée à droite).
- **`"registry:Card"` $\rightarrow$ `Card` / `Container` de Flutter** (`type: "native"` + entrée associée sous le même `id` dans `styles`) :
  - `child` (1 slot unique max) : composant enfant contenu dans la carte (souvent un `"registry:Layout"` pour organiser plusieurs sous-composants).
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
- `propertyBindings` & `states` : liaisons repository et surcharges par état (voir § 4.7).

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
- `propertyBindings` & `states` : liaisons repository et états nommés/automatiques (voir § 4.7).

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

### 4.6. `styles` (`ContainerStyle`) et ses bornes
- `color`, `borderColor`, `hoverColor` : `"#RRGGBB"` ou `"#AARRGGBB"`.
- `fill` : `{"type": "solid" | "linear" | "radial" | "sweep", "start": "#5268D9", "end": "#B794F4", "angle": 0..360, "radius": 0.1..2.0, "imageUrl": "https://...", "imageFit": "cover" | "contain" | "fill" | "fitWidth" | "fitHeight" | "none" | "scaleDown", "imageOpacity": 0..1}`.
- `radius` : **`0` à `36`** (ou `radii`: `[topLeft, topRight, bottomRight, bottomLeft]` de `0` à `36`).
- `borderWidth` : **`0` à `4`** (ou `borderWidths`: `[top, right, bottom, left]` de `0` à `4`), `borderLine`: `"solid"` | `"dashed"` | `"dotted"`.
- `elevation` : **`0` à `16`**, `shadowOpacity` : **`0` à `1`**.
- `padding`, `margin` : **`0` à `48`** (ou `paddingInsets`, `marginInsets`: `[top, right, bottom, left]` de `0` à `48`).
- `designSystem` : `"material"` | `"neumorphism"` | `"liquidGlass"`.
- `interactionEffect` : `"ripple"` | `"pressed"` | `"elevation"`.
- `hoverEffect` (`bool`), `hoverTint` (`"material"` | `"accent"` | `"custom"`).
- `opacity` (`0`..`1`), `backdropBlur` (`0`..`40`), `pattern` (`"none"` | `"grain"` | `"lines"` | `"dots"`), `patternOpacity` (`0`..`1`).
- `neon` : `true` ou `{"enabled": true, "color": "#00FFFF", "intensity": 0..3}`.
- `shadow` / `innerShadow` : `{"enabled": true, "color": "#000000", "opacity": 0..1, "blur": 0..48, "spread": -32..32, "dx": -32..32, "dy": -32..32}`.
- `transform` : `{"dx": -48..48, "dy": -48..48, "rotation": -180..180, "scale": 0.5..1.5}`.
- `states` : surcharges de surface par état (voir § 4.7).

### 4.7. États interactifs et styles conditionnels (`states`)

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

### 4.8. Comportements (`behaviors`) : Actions et navigation au clic

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
| **`ApplicationBar`** | Tant que `useDefaultNavigation` vaut `true` (défaut), Flutter affiche automatiquement le bouton menu (`Drawer`) ou retour (`BackButton`) à gauche, ainsi que les boutons système à droite. | N'ajoute pas de bouton menu/retour dans `leading` sauf si tu passes explicitement `"useDefaultNavigation": false`. |

---

## 6. Chat Vibe du mode édition

La bannière du mode édition ouvre un chat flottant et déplaçable. Chaque demande envoie à Gemini la conversation et l’export JSON courant de l’apparence. La réponse est appliquée avec `AppearanceTransfer.applyVibe` ; elle doit suivre la forme `{"message":"résumé","vibe":{"components":{...},"styles":{...}}}`.

Pour l’application de démonstration, la clé `GEMINI_API_KEY` peut être définie dans le fichier local `env` ou dans l’environnement du processus. Ne versionnez jamais cette clé. Les applications de production devraient appeler un service intermédiaire plutôt que d’embarquer une clé Gemini dans le client.
