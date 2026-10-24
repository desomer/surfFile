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
| **Types de placements** | `"registry:Layout"`, `"registry:Card"`, `"registry:Value"`, `"registry:Action"`, `"registry:ListView"`, `"registry:IterableContent"`, `"registry:ApplicationBar"`, `"registry:BottomNavigationBar"` | `"Layout"`, `"Card"`, `"Value"`, `"Action"`, `"Button"`, `"ListView"`, `"AppBar"`, `"BottomBar"` |

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
2. **`styles`** (`Map<String, ContainerStyle>`) : contient les styles visuels des surfaces (`background`, cartes `Card`, lignes de `ListView`, `IterableContent`).
3. **`pageCatalog`** : catalogue des pages routées (`pages`, `homePageId`).

### Exemple complet d'écran

```json
{
  "version": 1,
  "mode": "light",
  "accent": "#5268D9",
  "styles": {
    "background": { "color": "#F5F7FA", "padding": 12 },
    "card-detail": { "color": "#FFFFFF", "radius": 16, "padding": 20, "elevation": 3 },
    "list-clients": { "color": "#FFFFFF", "radius": 10, "hoverEffect": true }
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
    "contA": {
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
      "slotSizeConstraints": {
        "input-nom": { "preferredHeight": "64px", "padding": 8 }
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
  - `resizeSides` (`bool`) et `sideResizing` (`Map<Side, bool>`) : poignées de redimensionnement utilisateur.
  - `slotSizeConstraints` (`Map<slotId, SlotSizeConstraints>`) : contraintes de taille et marges par slot enfant.
  - `slotLabels` (`Map<slotId, string>`) : libellés personnalisés des slots.
  - `placements` (`Map<Zone, List<{"id": string, "type": string}>>`) : composants placés dans chaque zone.
- **`"grid"`** : Grille libre 2D (`columns` de `1` à `48`, `rowHeight` de `16` à `400`, `gap` de `0` à `64`).

### 4.2. `"native"` (`NativeComponentConfig`) & `"scaffold"` (`ScaffoldPageConfig`) — Lien avec les widgets Flutter Material
Les composants `"native"` et `"scaffold"` sont des adaptateurs directs vers les widgets structurels standards de la bibliothèque **Flutter Material** (`package:flutter/material.dart`). Leurs noms de régions dans `regions` et `placements` reprennent exactement les paramètres nommés des constructeurs Flutter correspondants :

- **Page / Écran (`"root"` ou `<pageId>` du `pageCatalog`) $\rightarrow$ `Scaffold` de Flutter** (`type: "native"` ou `"scaffold"`) :
  - `appBar` (1 slot max, dédié au composant `"registry:ApplicationBar"`) : barre supérieure du `Scaffold`.
  - `body` (empilement vertical, toujours actif) : contenu principal de la page. Pour `"root"`, contient par défaut `{"id": "scaffold:body", "type": "scaffold:body"}` qui monte le layout `"contA"`.
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

### 4.4. `"action"` (`SuperActionConfig`)
Affiche un bouton interactif :
- `kind` : `"text"` (défaut), `"icon"`, ou `"textAndIcon"`.
- `variant` : `"filled"` (défaut), `"tonal"`, `"elevated"`, `"outlined"`, `"text"`, `"icon"`, ou `"surface"`.
- `label` (ou `text`) : libellé du bouton (`string`, défaut `"Action"`).
- `tooltip` : infobulle (`string`).
- `icon` : identifiant d'icône du catalogue (`"touch_app"`, `"smart_button"`, `"add"`, `"edit"`, `"delete"`, `"check"`, `"close"`, `"search"`, `"settings"`, `"refresh"`, `"save"`, `"share"`, `"download"`, `"upload"`, `"arrow_back"`, `"arrow_forward"`, `"home"`, `"person"`, `"favorite"`, `"star"`, `"info"`, `"warning"`, `"play_arrow"`, `"send"`, `"more_vert"`, `"open_in_new"`, `"copy"`, `"filter_list"`, `"visibility"`, `"lock"`).
- `iconPosition` : `"leading"` (défaut) ou `"trailing"`.
- `iconSize` (`number > 0`), `iconSpacing` (`number >= 0`, défaut `8`).
- `enabled` (`bool`, défaut `true`).
- Typographie & Couleurs : `fontFamily`, `fontSize`, `fontWeight`, `italic`, `color`, `iconColor`, `backgroundColor`, `borderColor`, `radius`, `borderWidth`, `elevation`, `horizontalPadding`, `verticalPadding`, `textAlign`, `letterSpacing`.
- `style` (`ContainerStyle`) : style de surface avancé optionnel.
- `propertyBindings` & `states` : liaisons repository et états nommés/automatiques.

### 4.5. `"list"` (`SuperListViewConfig`)
Répète un gabarit `template` pour chaque élément d'un tableau JSON :
- `binding` : `"clients"` (si imbriquée) ou `{"repositoryId": "<32hex>", "path": "clients"}`.
- `axis` : `"vertical"` (défaut) ou `"horizontal"`.
- `wrap` : `bool` (`false` par défaut ; si `true`, disposition fluide en grille `Wrap`).
- `wrapSizing` : `"fixed"` ou `"automatic"`.
- `itemWidth` (`160`), `itemExtent` (`56`) : `number` entre **`16` et `2000`**.
- `spacing` (`0`) : `number` entre **`0` et `200`**.
- `allowAdd` (`false`), `allowRemove` (`false`) : `bool`.
- `emptyText` : `string` (`"Aucun élément"`).
- `template` (alias `"row"`) : `SuperLayoutConfig` embarqué décrivant la disposition des lignes. Le style visuel de la ligne est stocké sous le même `id` dans `styles[id]`.

### 4.6. `styles` (`ContainerStyle`) et ses bornes
- `color`, `borderColor`, `hoverColor` : `"#RRGGBB"` ou `"#AARRGGBB"`.
- `fill` : `{"type": "solid" | "linear" | "radial" | "sweep", "start": "#5268D9", "end": "#B794F4", "angle": 0..360, "radius": 0.1..2.0}`.
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

## 5. Chat Vibe du mode édition

La bannière du mode édition ouvre un chat flottant et déplaçable. Chaque demande envoie à Gemini la conversation et l’export JSON courant de l’apparence. La réponse est appliquée avec `AppearanceTransfer.applyVibe` ; elle doit suivre la forme `{"message":"résumé","vibe":{"components":{...},"styles":{...}}}`.

Pour l’application de démonstration, la clé `GEMINI_API_KEY` peut être définie dans le fichier local `env` ou dans l’environnement du processus. Ne versionnez jamais cette clé. Les applications de production devraient appeler un service intermédiaire plutôt que d’embarquer une clé Gemini dans le client.
