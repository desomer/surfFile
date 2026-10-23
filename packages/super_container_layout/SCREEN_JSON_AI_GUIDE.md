# Guide pour IA : Modéliser et configurer un écran en JSON (`super_container_layout`)

Ce document est une spécification technique destinée à une Intelligence Artificielle. Il explique comment générer le JSON de configuration d'un écran dans `super_container_layout` selon deux approches complémentaires :
1. **En 1 Phase (Arbre déclaratif imbriqué `screens`)** : décrire un écran complet dans une hiérarchie naturelle où chaque composant porte son style, sa taille et ses enfants.
2. **En mode "Vibe" (Étape par étape / Incrémental)** : construire ou retoucher un écran progressivement à l'aide de patchs partiels (**Deep Merge**) ou d'opérations atomiques (**`ops`**).

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
| **Types de composants** | `"Layout"`, `"Card"`, `"Value"`, `"ListView"`, `"IterableContent"`, `"ApplicationBar"`, `"BottomNavigationBar"` | Alias `"AppBar"`, `"BottomBar"`, `"List"` ou `"registry:<Type>"` |
| **Valeurs par défaut** | **Omises** : n'écris que les propriétés que tu souhaites personnaliser | Objet complet |

---

## 2. Mode 1-Phase : Créer un écran complet avec `screens`

Au lieu d'éclater la configuration dans plusieurs dictionnaires, tu peux déclarer tes écrans dans l'objet **`screens`** :
- **`"root"`** : représente l'écran principal de l'application (`SuperPage(id: "root")` dont le corps pilote le `SuperLayout` principal `"contA"`).
- **`"<pageId>"`** (ex: `"page-settings"`) : crée automatiquement une page routée dans `pageCatalog` si tu fournis `"path": "/settings"` et `"name": "Paramètres"` (et `"home": true` si c'est la page d'accueil).

### Anatomie d'un écran dans `screens`

Un écran possède les régions d'un `Scaffold` (`appBar`, `body`, `drawer`, `endDrawer`, `bottomNavigationBar`, `floatingActionButton`, `bottomSheet`), ou directement un objet `zones` s'il n'a qu'un corps en grille :

```json
{
  "mode": "light",
  "accent": "#5268D9",
  "styles": {
    "background": { "color": "#F5F7FA", "padding": 12 }
  },
  "screens": {
    "root": {
      "appBar": {
        "type": "ApplicationBar",
        "id": "main-appbar",
        "title": {
          "type": "Value",
          "id": "app-title",
          "text": "Gestion des Clients",
          "fontSize": 18,
          "fontWeight": "semibold"
        },
        "actions": [
          {
            "type": "Value",
            "id": "app-search",
            "mode": "input",
            "placeholder": "Rechercher...",
            "size": { "preferredWidth": "240px" },
            "field": {
              "variant": "outlined",
              "prefixIcon": "search",
              "suffix": "clear",
              "radius": 20,
              "dense": true
            }
          }
        ]
      },
      "body": {
        "type": "Layout",
        "id": "contA",
        "westSize": 260,
        "resizeSides": true,
        "zones": {
          "west": [
            {
              "type": "ListView",
              "id": "list-clients",
              "binding": {
                "repositoryId": "0123456789abcdef0123456789abcdef",
                "path": "clients"
              },
              "itemExtent": 56,
              "spacing": 8,
              "allowAdd": true,
              "allowRemove": true,
              "style": {
                "color": "#FFFFFF",
                "radius": 10,
                "padding": 10,
                "hoverEffect": true,
                "hoverTint": "accent"
              },
              "template": {
                "zones": {
                  "center": [
                    {
                      "type": "Value",
                      "id": "row-client-nom",
                      "text": "Nom du client",
                      "fontWeight": "medium",
                      "binding": "clients[?].nom"
                    }
                  ]
                }
              }
            }
          ],
          "center": [
            {
              "type": "Card",
              "id": "card-detail",
              "style": {
                "color": "#FFFFFF",
                "radius": 16,
                "padding": 20,
                "margin": 8,
                "elevation": 3
              },
              "child": {
                "type": "Layout",
                "id": "layout-form",
                "zones": {
                  "north": [
                    {
                      "type": "Value",
                      "id": "form-title",
                      "text": "Fiche du client sélectionné",
                      "fontSize": 20,
                      "fontWeight": "bold"
                    }
                  ],
                  "center": [
                    {
                      "type": "Value",
                      "id": "input-nom",
                      "mode": "input",
                      "label": "Nom complet",
                      "size": { "preferredHeight": "64px", "padding": 8 },
                      "binding": "0123456789abcdef0123456789abcdef:clients[?].nom"
                    },
                    {
                      "type": "Value",
                      "id": "input-email",
                      "mode": "input",
                      "label": "E-mail",
                      "size": { "preferredHeight": "64px", "padding": 8 },
                      "field": { "variant": "outlined", "prefixIcon": "email" },
                      "binding": "0123456789abcdef0123456789abcdef:clients[?].email"
                    },
                    {
                      "type": "Value",
                      "id": "input-actif",
                      "mode": "input",
                      "kind": "switch",
                      "label": "Client actif",
                      "value": true,
                      "size": { "preferredHeight": "48px", "padding": 8 },
                      "binding": "0123456789abcdef0123456789abcdef:clients[?].actif"
                    }
                  ]
                }
              }
            }
          ]
        }
      }
    }
  }
}
```

### Règles d'inférence automatiques en mode 1-Phase :
1. **Activation automatique des zones** : Dès que tu places un composant dans `zones.north`, `zones.south`, `zones.west` ou `zones.east` (ou dans un coin `nw`, `ne`, `sw`, `se`), les booléens `north: true`, `west: true`, etc. sont **activés automatiquement**.
2. **IDs optionnels** : Si tu omets `"id"` sur un composant imbriqué, un identifiant stable unique est généré automatiquement (`<parentId>_<zone>_<type>`). Il est toutefois recommandé de donner un `"id"` explicite (ex: `"card-detail"`) si tu souhaites le cibler plus tard en mode Vibe.
3. **Propriétés communes à tout slot placé** :
   - `"id"` : identifiant unique du composant.
   - `"type"` : `"Layout"`, `"Card"`, `"Value"`, `"ListView"`, `"IterableContent"`, `"ApplicationBar"`, `"BottomNavigationBar"` (peut même être omis si la forme de l'objet est non ambiguë : présence de `zones`, `child`, `template` ou `text`).
   - `"slotLabel"` : libellé affiché sur le badge du slot en mode édition.
   - `"size"` : contraintes de taille et marge du slot dans son parent :
     ```json
     "size": {
       "percentBasis": "zone",
       "padding": 8,
       "minWidth": "120px",
       "maxWidth": "80%",
       "preferredWidth": "240px",
       "preferredHeight": "64px"
     }
     ```

---

## 3. Mode "Vibe" : Construire et modifier un écran étape par étape

En mode Vibe (`AppearanceTransfer.applyVibe` ou via l'import avec `"mode": "vibe"` / `"ops"`), tu n'as **pas besoin de renvoyer tout l'écran**. Tu peux envoyer uniquement les modifications souhaitées à chaque étape grâce au tableau **`"ops"`** (ou via un objet partiel avec `"merge": true`).

### Les 6 opérations atomiques du mode Vibe (`"ops"`)

#### 1. `"add"` (Ajouter ou remplacer un composant / sous-arbre dans une zone)
Ajoute un composant (ou tout un sous-arbre imbriqué) dans une zone d'un `Layout` ou une région d'une `Page` / `Card` / `ApplicationBar`, et active automatiquement la zone :
```json
{
  "ops": [
    {
      "op": "add",
      "target": "contA",
      "zone": "east",
      "node": {
        "type": "Card",
        "id": "card-stats",
        "style": { "color": "#FFFFFF", "radius": 12, "padding": 16 },
        "child": {
          "type": "Value",
          "id": "stats-title",
          "text": "Statistiques",
          "fontSize": 16,
          "fontWeight": "bold"
        }
      }
    }
  ]
}
```
- Paramètres optionnels de `"add"` :
  - `"beforeId"` / `"afterId"` : insère le composant juste avant ou après un slot existant dans la zone.
  - `"replace": true` : vide la zone cible avant d'insérer le(s) nouveau(x) composant(s).

#### 2. `"patch"` (Modifier partiellement un composant, un style ou une disposition)
Modifie uniquement les propriétés précisées sur un composant existant, **sans écraser ses autres réglages** :
```json
{
  "ops": [
    {
      "op": "patch",
      "id": "card-detail",
      "style": {
        "radius": 24,
        "designSystem": "neumorphism",
        "elevation": 6
      }
    },
    {
      "op": "patch",
      "id": "app-title",
      "text": "Nouveau Titre CRM",
      "color": "#5268D9"
    },
    {
      "op": "patch",
      "id": "contA",
      "layout": {
        "westSize": 300
      }
    }
  ]
}
```
- Tu peux aussi modifier la taille ou le badge d'un slot dans son parent :
  `{"op": "patch", "id": "input-nom", "size": {"preferredHeight": "72px", "padding": 12}}`.

#### 3. `"move"` (Déplacer un composant d'une zone à une autre)
```json
{
  "ops": [
    {
      "op": "move",
      "target": "contA",
      "id": "card-stats",
      "zone": "south",
      "beforeId": "other-slot"
    }
  ]
}
```

#### 4. `"remove"` (Supprimer un composant et nettoyer ses données)
```json
{
  "ops": [
    {
      "op": "remove",
      "target": "contA",
      "id": "card-stats"
    }
  ]
}
```

#### 5. `"upsertPage"` (Créer ou mettre à jour une page routée)
```json
{
  "ops": [
    {
      "op": "upsertPage",
      "id": "page-settings",
      "name": "Paramètres",
      "path": "/settings",
      "home": false,
      "body": {
        "type": "Layout",
        "id": "layout-settings",
        "zones": {
          "center": [
            {
              "type": "Value",
              "id": "toggle-notif",
              "mode": "input",
              "kind": "switch",
              "label": "Activer les notifications",
              "value": true
            }
          ]
        }
      }
    }
  ]
}
```

#### 6. `"removePage"` (Supprimer une page routée)
```json
{
  "ops": [
    {
      "op": "removePage",
      "id": "page-settings"
    }
  ]
}
```

---

## 4. Référence des composants et de leurs propriétés

### 4.1. `Layout` (`SuperLayoutConfig`)
Dispose ses enfants selon 2 modes (`"positioning"`) :
- **`"zones"` (par défaut)** : Grille 3×3 (`nw`, `north`, `ne`, `west`, `center`, `east`, `sw`, `south`, `se`).
  - `north`, `south`, `west`, `east` (`bool`) : activés automatiquement si leur zone contient des éléments dans `zones`.
  - `northSize`, `southSize`, `westSize`, `eastSize` (`number`, **bornes : `24` à `400`**) : épaisseur en pixels des côtés fixes.
  - `autoSides` (`List<string>`) : côtés (`"north"`, `"south"`, `"west"`, `"east"`) dont l'épaisseur s'adapte automatiquement à leur contenu.
  - `nw`, `ne`, `sw`, `se` : `"none"` (case propre), `"row"` (absorbé par Nord/Sud), `"column"` (absorbé par Ouest/Est).
  - `zoneAxes` (`Map<Zone, "row" | "column">`) : axe d'empilement des composants par zone (`"column"` par défaut).
  - `resizeSides` (`bool`) et `sideResizing` (`Map<Side, bool>`) : poignées de redimensionnement utilisateur.
- **`"grid"`** : Grille libre 2D :
  ```json
  {
    "type": "Layout",
    "id": "dashboard-grid",
    "positioning": "grid",
    "grid": {
      "columns": 12,
      "rowHeight": 64,
      "gap": 8,
      "compact": true,
      "items": {
        "kpi-1": { "x": 0, "y": 0, "width": 6, "height": 2 },
        "kpi-2": { "x": 6, "y": 0, "width": 6, "height": 2 }
      }
    },
    "zones": {
      "center": [
        { "type": "Card", "id": "kpi-1", "style": { "radius": 12 } },
        { "type": "Card", "id": "kpi-2", "style": { "radius": 12 } }
      ]
    }
  }
  ```
  *(Contraintes `grid` : `columns` de `1` à `48`, `rowHeight` de `16` à `400`, `gap` de `0` à `64`, aucun chevauchement entre les rectangles `items`).*

### 4.2. `Card` (`EditableSurface` + enfant unique)
- `"style"` : objet `ContainerStyle` (voir 4.6).
- `"child"` : un composant enfant unique (ex: un `"Layout"` ou un `"Value"`).

### 4.3. `Value` (`SuperValueConfig`)
Affiche un texte, un champ de saisie, une case à cocher ou un interrupteur :
- `mode` : `"display"` (défaut) ou `"input"`.
- `kind` : `"text"` (défaut), `"checkbox"` ou `"switch"` (`"switchControl"`).
- `text` (ou `initialText`) : texte initial (`string`).
- `value` (ou `initialBool`) : valeur booléenne initiale (`bool`) pour `checkbox` / `switch`.
- `label`, `placeholder` : `string`.
- `enabled` (`true`), `readOnly` (`false`), `obscureText` (`false`) : `bool`.
  - *Note* : si `obscureText: true`, exige `kind: "text"`, `minLines: 1`, `maxLines: 1`, et pas de texte initial non vide.
- `minLines` (`1`), `maxLines` (`1`) : `int` (`maxLines >= minLines >= 1`).
- Typographie : `fontFamily` (`string`), `fontSize` (`number > 0`), `fontWeight` (`"light"`, `"normal"`, `"medium"`, `"semibold"`, `"bold"` ou `100`..`900`), `italic` (`bool`), `color` (`"#RRGGBB"`), `textAlign` (`"start"`, `"center"`, `"end"`, `"left"`, `"right"`, `"justify"`), `lineHeight` (`number > 0`), `letterSpacing` (`number`).
- `binding` : `"clients[?].nom"` ou `{"repositoryId": "...", "path": "..."}`.
- `field` (`SuperTextFieldConfig`, pour `mode: "input"`) :
  - `variant` : `"theme"`, `"filled"`, `"outlined"`, `"underline"`, `"borderless"`.
  - Couleurs : `fillColor`, `focusFillColor`, `borderColor`, `focusBorderColor`, `errorBorderColor` (`"#RRGGBB"`).
  - Dimensions : `radius`, `borderWidth`, `horizontalPadding`, `verticalPadding` (`number >= 0`), `dense` (`bool`).
  - Ornement : `prefixText`, `suffixText`, `helperText`, `errorText`, `prefixIcon` / `suffixIcon` (`"person"`, `"email"`, `"phone"`, `"search"`, `"lock"`, `"link"`, `"home"`, `"calendar"`, `"info"`, `"check"`), `suffix` (`"decoration"`, `"clear"`, `"visibility"`).
  - Saisie : `maxLength` (`int >= 1`), `showCounter` (`bool`), `filter` (`"none"`, `"digits"`, `"decimal"`, `"letters"`, `"pattern"`), `pattern` (regex non vide), `keyboard` (`"automatic"`, `"text"`, `"multiline"`, `"email"`, `"phone"`, `"url"`, `"number"`, `"decimal"`, `"signedDecimal"`), `action` (`"automatic"`, `"done"`, `"next"`, `"previous"`, `"search"`, `"send"`, `"go"`, `"newline"`).

### 4.4. `ListView` (`SuperListViewConfig`)
Répète un gabarit `template` pour chaque élément d'un tableau JSON :
- `binding` : `"clients"` (si imbriquée) ou `{"repositoryId": "<32hex>", "path": "clients"}`.
- `axis` : `"vertical"` (défaut) ou `"horizontal"`.
- `wrap` : `bool` (`false` par défaut ; si `true`, disposition fluide en grille `Wrap`).
- `wrapSizing` : `"fixed"` ou `"automatic"`.
- `itemWidth` (`160`), `itemExtent` (`56`) : `number` entre **`16` et `2000`**.
- `spacing` (`0`) : `number` entre **`0` et `200`**.
- `allowAdd` (`false`), `allowRemove` (`false`) : `bool`.
- `emptyText` : `string` (`"Aucun élément"`).
- `style` : `ContainerStyle` appliqué à chaque ligne de la liste.
- `template` : `SuperLayoutConfig` (contenant `"zones": { ... }`) décrivant les composants à l'intérieur d'une ligne. Les `Value` placés dans `template` utilisent `"binding": "clients[?].champ"` (le `repositoryId` est automatiquement hérité de la liste !).

### 4.5. `ApplicationBar` & `BottomNavigationBar`
- **`ApplicationBar`** (uniquement dans la région `"appBar"` d'un écran) :
  - `useDefaultNavigation` (`bool`) : bouton burger/retour automatique (`true` par défaut ; mettre `false` pour personnaliser `leading`).
  - Régions : `leading` (1 slot max), `title` (horizontal), `actions` (horizontal), `bottom` (1 slot max), `flexibleSpace` (1 slot max).
- **`BottomNavigationBar`** (uniquement dans la région `"bottomNavigationBar"` d'un écran) :
  - Régions : `left`, `center`, `right` (horizontales).

### 4.6. `style` (`ContainerStyle`) et ses bornes
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

