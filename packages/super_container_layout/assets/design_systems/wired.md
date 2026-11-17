---
name: "WIRED Editorial"
slug: "wired"
category: "media-retail"
tagline: "Grille de presse tech radicale, angles vifs à 0px, filets noirs graphiques et rouge éditorial."
description: "Système éditorial incisif inspiré des grands magazines technologiques : papier blanc #FFFFFF, encarts gris presse #F4F4F4, coins strictement orthogonaux à 0px, filets noirs #000000 de 1 à 2px et titraille Georgia associée à des étiquettes monospace. Idéal pour les portails médias, salles de rédaction, veilles stratégiques et rapports exécutifs."
mode: "light"
accent: "#E51212"
canvasColor: "#FFFFFF"
surfaceColor: "#F4F4F4"
textColor: "#000000"
mutedTextColor: "#525252"
borderColor: "#000000"
cardRadius: 0
surfaceSystem: "material"
fontFamily: "Georgia"
---

# WIRED Editorial — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
Le style **WIRED Editorial** rompt délibérément avec les arrondis doux du SaaS conventionnel pour imposer l'autorité graphique d'une maquette de presse contemporaine. Chaque angle est coupé au rasoir (`radius: 0`), chaque colonne ou encart est scandé par des filets d'encre noire `#000000` (`1px` à `2px`) sur papier blanc `#FFFFFF` ou trame gris journal `#F4F4F4`. Le dialogue entre les titres à empattements `"Georgia"`, les rubriques techniques en chasse fixe `"Consolas"` et les accents rouge signal `#E51212` produit une tension intellectuelle immédiate et ultra-lisible.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Papier principal (Canvas)** | `#FFFFFF` | `styles["background"].color` (padding `0`) |
| **Encart éditorial / Dossier** | `#F4F4F4` | `styles["<cardId>"].color` pour blocs d'analyse, encadrés et KPI |
| **Encre typographique & Filets** | `#000000` | `textColor` primaire et `borderColor` graphique (`1px`–`2px`) |
| **Gris de rédaction (Muted)** | `#525252` | Chapeaux, signatures, légendes, horodatages (`SuperValue`) |
| **Rouge éditorial (Signal)** | `#E51212` | `accent` racine, rubriques phares, CTA d'alerte/publication |
| **Sélection de dépêche / Ligne** | `#FFEBEB` | Fond `states.selected` des articles/items avec filet `#E51212` (`2px`) |
| **Filet secondaire interne** | `#D4D4D4` | Séparateurs fins internes aux tableaux pour éviter la surcharge |
| **Badges rubriques (Exclusif / Enquête)** | `#000000` / `#E51212` | `SuperIndicator` rectangulaires (`radius: 0`) à texte `#FFFFFF` |

## 3. Typography Rules
Associer **trois voix typographiques complémentaires** : **`"Georgia"`** pour les grandes manchettes de presse et chiffres phares, **`"Inter"`** pour la lecture fluide du corps d'article et des tableaux, et **`"Consolas"`** pour les surtitres de rubrique (kickers), index, horodatages et métriques techniques.

| Niveau `SuperValue` | Police (`fontFamily`) | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Manchette / KPI Majeur** | `"Georgia"` | `24`–`26` | `"bold"` | `#000000` | Grand titre de une, chiffre clé d'audience ou d'enquête |
| **2. Titre d'encart / Rubrique** | `"Georgia"` | `17`–`18` | `"bold"` | `#000000` | Titre de `Card` dossier, fiche d'article ou section |
| **3. Corps / Cellule / Champ** | `"Inter"` | `13`–`14` | `"normal"` (`"semibold"` en titre) | `#000000` | Texte courant, entrées de `ListView` et `SuperTable` |
| **4. Kicker / Dateline / Index** | `"Consolas"` | `11`–`12` | `"semibold"` | `#525252` (ou `#E51212`) | Catégorie courte, heure de publication, code dossier |

## 4. Component Stylings
- **Encarts & Cartes (`Card` / `IterableContent`)** : `designSystem: "material"`, `color: "#F4F4F4"` (ou `"#FFFFFF"`), **`radius: 0` strict**, `padding: 16` ou `20`, `borderWidth: 2` sur les blocs majeurs (`1` sur les blocs secondaires), `borderColor: "#000000"`, `elevation: 0` (titres en `"Georgia"`, corps en `"Inter"`).
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : `backgroundColor: "#E51212"` (ou `"#000000"` pour une action éditoriale sobre), `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AA élevé), **`radius: 0`**, `fontFamily: "Consolas"`, `fontWeight: "bold"`, `letterSpacing: 0.6`, `horizontalPadding: 16`, `verticalPadding: 10`.
  - *Secondaire (`variant: "outlined"`)* : `fontFamily: "Inter"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#000000"`, `borderWidth: 1`, `color: "#000000"`, `iconColor: "#000000"`, `radius: 0`.
- **Champs & Valeurs (`SuperValue`)** : `fontFamily: "Inter"`, `radius: 0` en saisie, 1 `SuperValue` atomique par attribut métier en consultation (`label` précis + valeur).
- **Listes de dépêches & Tableaux (`<listId>:item` & `SuperTable`)** : `color: "#FFFFFF"`, `radius: 0`, `padding: 12`, `borderWidth: 1`, `borderColor: "#D4D4D4"`, `hoverEffect: true`, `hoverColor: "#F4F4F4"`. `states.selected` : `color: "#FFEBEB"`, `borderWidth: 2`, `borderColor: "#E51212"`.
- **Étiquettes de rubrique (`SuperIndicator`)** : cartouches rectangulaires francs **`radius: 0`**, `horizontalPadding: 8`, `verticalPadding: 4`, `fontFamily: "Consolas"`, `backgroundColor: "#000000"` (ou `"#E51212"` pour `"URGENT"` / `"LIVE"`) avec `color: "#FFFFFF"` et `iconColor: "#FFFFFF"`.

## 5. Layout Principles
- **Rigueur modulaire de maquette** : espacements `4, 8, 12, 16, 20, 24`. `styles["background"].padding` vaut `0`. Privilégier `padding: 16` et `spacing: 16` dans `zoneFlows` pour laisser les cadres noirs structurer l'écran comme les colonnes d'un journal.
- **Orthogonalité totale (`radius: 0`)** : la règle concentrique se traduit ici par **`radius: 0` à tous les niveaux** (cartes, sous-conteneurs, lignes de liste, boutons, champs et badges). Aucun coin arrondi ne doit rompre la ligne graphique.
- **Collections éditoriales Desktop** : `ListView` d'articles/dossiers à `itemExtent: 56`–`64` (`spacing: 6`), `SuperTable` analytique à `headerRowHeight: 38` et `rowHeight: 38`, `SuperSeparator` horizontal (`thickness: 2`, `lineColor: "#000000"`) utile pour souligner un grand titre de section.

## 6. Depth & Elevation
Zéro flou et zéro ombre diffuse : fixer `designSystem: "material"` et **`elevation: 0`** sur tous les conteneurs. L'autorité visuelle provient intégralement du graphisme planaire (cadres `1px`–`2px #000000` et aplats `#F4F4F4` sur `#FFFFFF`).

## 7. Do's and Don'ts
- **Do** : Appliquer systématiquement `radius: 0` sur les cartes, boutons, lignes et badges `SuperIndicator`.
- **Do** : Combiner `"Georgia"` pour les titres majeurs et `"Consolas"` pour les étiquettes courtes et compteurs.
- **Do** : Utiliser `#E51212` comme signal éditorial ponctuel (un seul CTA rouge ou badge prioritaire par zone).
- **Do** : Structurer les synthèses d'articles ou de dossiers en champs atomiques (`SuperValue`), jamais en faux paragraphes fourre-tout.
- **Don't** : Ne jamais introduire de rayons arrondis (`radius: 8`, `12` ou `99`) qui détruisent instantanément l'identité presse.
- **Don't** : Ne jamais ajouter d'ombres portées molles (`elevation > 0`) sous des cadres déjà cernés de noir `#000000`.
- **Don't** : Ne jamais rédiger de longs textes courants tout en majuscules ni en `"Consolas"`.
- **Don't** : Ne jamais imbriquer de `Card` à l'intérieur de `list.template.placements`.

## 8. Responsive & Desktop Ergonomics
- **Salle de rédaction Maître / Détail** : `west: true`, `westSize: 330`, `resizeSides: true`, `autoSides: []`. Le flux des dépêches/sujets réside en `west`, et l'article ou le dossier complet s'ouvre en `center` (`expandSlots: true`).
- **Bandeau Chiffres Clés (Masthead KPI)** : zone `north` (`northSize: 108`, `zoneAxes.north: "row"`, `spacing: 12`, `expandSlots: true`) alignant 3 à 4 encarts `#F4F4F4` bordés `2px #000000` avec métriques en `"Georgia"`.
- **Formulaire de soumission / édition** : colonne de lecture maîtrisée (`maxWidth: "740px"`), `scrollable: true` et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "light",
  "accent": "#E51212",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#F4F4F4",
      "radius": 0,
      "padding": 20,
      "borderWidth": 2,
      "borderColor": "#000000",
      "elevation": 0
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 0,
      "padding": 12,
      "borderWidth": 1,
      "borderColor": "#D4D4D4",
      "hoverEffect": true,
      "hoverColor": "#F4F4F4",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#FFEBEB",
            "borderWidth": 2,
            "borderColor": "#E51212"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "headline-main": {
      "type": "value",
      "text": "L'Ère des Systèmes Autonomes",
      "fontFamily": "Georgia",
      "fontSize": 26,
      "fontWeight": "bold",
      "color": "#000000"
    },
    "kicker-tag": {
      "type": "indicator",
      "icon": "flag",
      "label": "ENQUÊTE SPÉCIALE",
      "fontFamily": "Consolas",
      "fontSize": 11,
      "fontWeight": "bold",
      "color": "#FFFFFF",
      "iconColor": "#FFFFFF",
      "backgroundColor": "#E51212",
      "radius": 0,
      "horizontalPadding": 8,
      "verticalPadding": 4
    }
  }
}
```
