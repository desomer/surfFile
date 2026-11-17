---
name: "Claude"
slug: "claude"
category: "ai-platforms"
tagline: "Parchemin éditorial chaleureux, sérifs littéraires et accents terre cuite apaisés."
description: "Langage visuel humaniste associant un canevas parchemin chaud (#FAF9F5), des surfaces pierre douce (#F0EEE6) finement bordées et une typographie éditoriale Georgia mêlée à un corps sans-serif net. Idéal pour les assistants IA conversationnels, studios de rédaction, bases de connaissances et outils de recherche analytique."
mode: "light"
accent: "#D97757"
canvasColor: "#FAF9F5"
surfaceColor: "#F0EEE6"
textColor: "#141413"
mutedTextColor: "#6B6963"
borderColor: "#E3E0D6"
cardRadius: 12
surfaceSystem: "material"
fontFamily: "Georgia"
---

# Claude — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
Cette direction esthétique remplace la froideur clinique des interfaces technologiques bleutées par la chaleur calme d'un carnet d'édition sur papier vélin. Le fond parchemin `#FAF9F5` absorbe l'éblouissement sur grand écran Desktop, tandis que les panneaux secondaires en avoine douce `#F0EEE6` et les cartes de lecture `#FFFFFF` structurent l'espace sans ombres lourdes. L'atmosphère privilégie la concentration longue durée, la lisibilité littéraire et une ponctuation chromatique mesurée autour du terre cuite `#D97757`.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas global** | `#FAF9F5` | `styles["background"].color` — fond parchemin principal sans padding (`0`) |
| **Surface secondaire (Avoine)** | `#F0EEE6` | Panneaux latéraux (`west`), barres d'invite, conteneurs de contexte |
| **Surface de lecture pure** | `#FFFFFF` | Cartes d'artefacts, fiches détaillées ou zones d'édition principales |
| **Bordure éditoriale** | `#E3E0D6` | Filet `1px` systématique sur `Card`, `Table` et champs au repos |
| **Encre principale** | `#141413` | Titres, valeurs clés et texte de lecture principal (`SuperValue`) |
| **Encre secondaire** | `#6B6963` | Métadonnées, horodatages, sous-titres et labels discrets |
| **Accent Terre Cuite** | `#D97757` | Racine `"accent"`, bouton primaire `filled`, curseur et focus actif |
| **Surface sélectionnée** | `#F5E6DF` | Fond de ligne active (`states.selected`) avec bordure `#D97757` |
| **Succès / Validation** | `#2E6F40` | Pastilles d'état actif sur fond `#E6F2EA` |
| **Alerte / Destruction** | `#B83A2D` | Actions critiques et badges d'erreur sur fond `#FCEBE9` |

## 3. Typography Rules
Associez **`"Georgia"`** pour les titres littéraires et en-têtes éditoriaux avec **`"Inter"`** (ou `"Segoe UI"`) pour les contrôles d'interface nets, formulaires et corps de lecture, et **`"JetBrains Mono"`** (ou `"Consolas"`) pour les extraits de code, compteurs de jetons et identifiants de modèles.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Titre éditorial / KPI** | `"Georgia"` | `24` | `"semibold"` | `"#141413"` | En-tête de vue, message d'accueil ou métrique phare |
| **2. Titre de carte / Section** | `"Georgia"` | `17` | `"semibold"` | `"#141413"` | Titre de `Card`, d'artefact ou de volet latéral |
| **3. Corps / Champ / Ligne** | `"Inter"` | `14` | `"normal"` / `"medium"` | `"#141413"` | Lecture courante (`lineHeight: 1.5`), saisie `input`, cellules |
| **4. Métadonnée / Code / Jetons** | `"Inter"` / `"JetBrains Mono"` | `12` | `"normal"` | `"#6B6963"` | Date et libellé (`Inter`), modèle actif et jetons (`JetBrains Mono` / `Consolas`) |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#F0EEE6"` (volet/contexte) ou `"#FFFFFF"` (document/artefact), `radius: 12`, `borderWidth: 1`, `borderColor: "#E3E0D6"`, `elevation: 0`, `padding: 20`.
- **Boutons (`SuperAction`)** :
  - Primaire (`variant: "filled"`) : `backgroundColor: "#D97757"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 8`, `horizontalPadding: 16`, `verticalPadding: 10` (contraste AA net).
  - Secondaire (`variant: "outlined"`) : `backgroundColor: "#FAF9F5"`, `borderColor: "#D5D1C5"`, `borderWidth: 1`, `color: "#141413"`, `iconColor: "#6B6963"`, `radius: 8`.
  - Tertiaire / Barre d'outils (`variant: "icon"` ou `"text"`) : `color: "#6B6963"`, `iconColor: "#6B6963"` avec `tooltip` explicite.
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : fond `"#FFFFFF"`, bordure `1px` `"#E3E0D6"`, `radius: 10`, focus surchargé avec `color: "#141413"` et `placeholder` naturel sans redondance avec `label`.
- **Collections (`ListView` / `Table`)** : lignes `styles["<listId>:item"]` avec `color: "#00000000"`, `radius: 8`, `padding: 10`, `hoverEffect: true`, et `states.selected` appliquant `color: "#F5E6DF"`, `borderColor: "#D97757"`, `borderWidth: 1`.
- **Pastilles (`SuperIndicator`)** : `radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4` ; état nominal en `backgroundColor: "#E8E5DC"`, `color: "#141413"`, `iconColor: "#6B6963"` ; état actif IA en `backgroundColor: "#F5E6DF"`, `color: "#9E472A"`, `iconColor: "#D97757"`.

## 5. Layout Principles
- **Échelle d'espacement** : utilisez strictement `4, 8, 12, 16, 20, 24`. Laissez `styles["background"].padding` à `0` et appliquez `padding: 16` ou `20` sur `zoneFlows` et les `Card` (`padding >= spacing` obligatoire).
- **Rayons concentriques** : `Card` externe à `12px` $\rightarrow$ sous-panneaux/champs d'invite à `10px` $\rightarrow$ boutons et lignes de liste à `8px`.
- **Calibrage Desktop des collections** : `ListView` d'historique ou de documents à `itemExtent: 52` (`spacing: 4`) ; `SuperTable` analytique à `headerRowHeight: 38`, `rowHeight: 38` avec texte aligné à `"start"` et métriques à `"end"`.

## 6. Depth & Elevation
- **Système unique** : `"designSystem": "material"` sur toutes les surfaces, sans jamais activer `liquidGlass`, `neumorphism` ni `neon`.
- **Profondeur papetière plate** : privilégiez `elevation: 0` et différenciez les plans par le couple luminance + filet `#E3E0D6` (`#FAF9F5` pour le canevas $\rightarrow$ `#F0EEE6` pour la navigation/contexte $\rightarrow$ `#FFFFFF` pour la feuille active avec `elevation: 1` et `shadowOpacity: 0.05` maximum).

## 7. Do's and Don'ts
- **Do** : Réserver `"Georgia"` aux titres de niveau 1 et 2 pour signer l'identité littéraire tout en gardant `"Inter"` sur les données tabulaires et contrôles, et `"JetBrains Mono"` sur les jetons/extraits techniques.
- **Do** : Limiter l'accent `#D97757` à un unique bouton primaire par zone et aux indicateurs d'état actif (règle 60-30-10).
- **Do** : Utiliser un seul `SuperValue` (`label` + `binding`/`text`) pour chaque attribut métier consulté en mode `"display"`.
- **Do** : Configurer un `emptyText` chaleureux et précis en français (ex. `"Aucune conversation enregistrée dans ce projet"`).
- **Don't** : Ne jamais utiliser de gris bleutés froids (`#F1F5F9`, `#64748B`) ni de noir RVB pur `#000000` qui rompent l'harmonie chaude du parchemin.
- **Don't** : Ne jamais imbriquer plusieurs `Card` bordées les unes dans les autres (« poupées russes »).
- **Don't** : Ne jamais étirer un bouton `"filled"` terre cuite sur toute la largeur d'une colonne Desktop.
- **Don't** : Ne jamais composer de récapitulatif métier sous forme de `textarea` multiligne libre.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Conversations, Projets, Artefacts)** : sur `mainLayout`, activez `west: true`, `westSize: 300` (ou `320`), `resizeSides: true`, avec `"autoSides": []` (jamais `"west"` dans `autoSides`). Logez la liste défilante en `center` du volet gauche (`expandSlots: true`) et l'espace de lecture/artefact en `center` de `mainLayout`.
- **Bandeau KPI / Synthèse** : en zone `north`, alignez 3 à 4 cartes sobres en `row` (`spacing: 12`, `northSize: 108`).
- **Confort de lecture et formulaires** : bornez les panneaux de rédaction ou de réglages à `maxWidth: "760px"` (`crossAxisAlignment: "center"`) et retirez systématiquement `autoSides` sur tout layout ayant `scrollable: true`.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour initialiser l'atmosphère éditoriale Claude :

```json
{
  "mode": "light",
  "accent": "#D97757",
  "components": {
    "title-editorial": {
      "type": "value",
      "text": "Atelier de synthèse",
      "fontFamily": "Georgia",
      "fontSize": 24,
      "fontWeight": "semibold",
      "color": "#141413"
    },
    "val-tokens": {
      "type": "value",
      "label": "Contexte actif",
      "text": "18 420 tokens",
      "fontFamily": "JetBrains Mono",
      "fontSize": 12,
      "color": "#6B6963"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#FAF9F5",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 12,
      "borderWidth": 1,
      "borderColor": "#E3E0D6",
      "elevation": 1,
      "shadowOpacity": 0.04,
      "padding": 20
    },
    "card-sidebar": {
      "designSystem": "material",
      "color": "#F0EEE6",
      "radius": 12,
      "borderWidth": 1,
      "borderColor": "#E3E0D6",
      "elevation": 0,
      "padding": 16
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 8,
      "padding": 10,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#F5E6DF",
            "borderColor": "#D97757",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
