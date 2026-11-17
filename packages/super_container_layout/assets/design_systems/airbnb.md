---
name: "Airbnb"
slug: "airbnb"
category: "media-retail"
tagline: "Hospitalité chaleureuse, cartes accueillantes bordées #DDDDDD et corail signature #FF385C."
description: "Langage visuel lumineux et convivial associant un canevas blanc pur #FFFFFF, des surfaces douces #F7F7F7 encadrées de filets #DDDDDD aux coins généreux et une touche corail #FF385C. Idéal pour les marketplaces, portails de réservation, catalogues immobiliers, CRM clients et expériences retail."
mode: "light"
accent: "#FF385C"
canvasColor: "#FFFFFF"
surfaceColor: "#F7F7F7"
textColor: "#222222"
mutedTextColor: "#6A6A6A"
borderColor: "#DDDDDD"
cardRadius: 16
surfaceSystem: "material"
fontFamily: "Plus Jakarta Sans"
---

# Airbnb — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
L'atmosphère **Airbnb** marie clarté éditoriale et chaleur humaine. Contrairement aux interfaces SaaS grises et austères, le canevas reste d'un blanc lumineux `#FFFFFF` qui maximise la sensation d'espace et la fraîcheur des contenus, tandis que les panneaux secondaires adoptent un gris pierre très doux `#F7F7F7` ou un fond `#FFFFFF` serti d'une bordure franche `#DDDDDD` (`radius: 16`, `padding: 20`). Le charbon doux `#222222` remplace le noir dur pour une lecture apaisée, relevée au moment de l'engagement par le corail signature `#FF385C`.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas lumineux** | `#FFFFFF` | `styles["background"].color` (padding `0`) |
| **Surface douce / Panneau** | `#F7F7F7` | `styles["<cardId>"].color` pour volets de filtres, résumés et encarts |
| **Carte de fiche / Détail** | `#FFFFFF` | Cartes principales encadrées par `borderColor: "#DDDDDD"` (`1px`) |
| **Encre primaire (Charcoal)** | `#222222` | Titres d'annonces, prix clés, libellés principaux (`SuperValue`) |
| **Encre secondaire (Neutral)** | `#6A6A6A` | Dates, localisations, capacités, sous-titres et notes |
| **Accent primaire (Rausch)** | `#FF385C` | `accent` racine, bouton d'action principal `SuperAction` |
| **Teinte de sélection** | `#FFF0F3` | Fond `states.selected` des cartes/lignes actives avec contour `#FF385C` |
| **Bordure conviviale** | `#DDDDDD` | `borderColor` (`1px`) délimitant cartes, champs et barres de filtres |
| **Statuts (Confirmé / Attente / Annulé)** | `#008A05` / `#C13515` | `SuperIndicator` sur pastilles `#EBF8EC` (vert) et `#FFF0ED` (terre cuite) |

## 3. Typography Rules
Privilégier **`"Plus Jakarta Sans"`** (sans-serif géométrique-humaniste chaleureuse aux courbes ouvertes, avec repli sur `"Segoe UI"`) et des graisses franches (`"semibold"`) sur les titres et les tarifs, tout en conservant des interlignes confortables et un ton naturel en français.

| Niveau `SuperValue` | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Titre d'accueil / Tarif clé** | `"Plus Jakarta Sans"` | `22`–`26` | `"semibold"` | `#222222` | En-tête de catalogue, revenu total ou tarif par nuitée mis en avant |
| **2. Titre de Carte / Section** | `"Plus Jakarta Sans"` | `16`–`18` | `"semibold"` | `#222222` | Titre d'une fiche logement/client, d'un bloc récapitulatif |
| **3. Corps / Attribut / Ligne** | `"Plus Jakarta Sans"` | `14` | `"normal"` (`"medium"` pour le titre d'item) | `#222222` | Champs atomiques, lignes de réservation, cellules `SuperTable` |
| **4. Détail / Sous-titre / Aide** | `"Plus Jakarta Sans"` | `12` | `"normal"` | `#6A6A6A` | Période de séjour, ville, statut secondaire, conditions courtes |

## 4. Component Stylings
- **Cartes & Encarts (`Card` / `IterableContent`)** : `designSystem: "material"`, `color: "#F7F7F7"` (ou `"#FFFFFF"` pour une fiche mise en relief par une ombre douce), `radius: 16`, `padding: 20`, `borderWidth: 1`, `borderColor: "#DDDDDD"`, `elevation: 1`, `shadowOpacity: 0.06`.
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : réservé au CTA d'engagement (ex. `"Réserver"`, `"Confirmer"`, `"Publier l'offre"`), `fontFamily: "Plus Jakarta Sans"`, `backgroundColor: "#FF385C"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AA), `radius: 10`, `fontWeight: "semibold"`, `horizontalPadding: 18`, `verticalPadding: 12`.
  - *Secondaire (`variant: "outlined"`)* : style éditorial net `fontFamily: "Plus Jakarta Sans"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#222222"`, `borderWidth: 1`, `color: "#222222"`, `iconColor: "#222222"`, `radius: 10`.
- **Champs & Filtres (`SuperValue`)** : `fontFamily: "Plus Jakarta Sans"`. En saisie (`mode: "input"`), labels limpides et `variant: "filterChip"` ou `"segmented"` pour filtrer rapidement catégories, statuts ou équipements. En lecture, 1 `SuperValue` atomique par information.
- **Listes & Tableaux (`<listId>:item`)** : `color: "#FFFFFF"`, `radius: 12`, `padding: 12`, `borderWidth: 1`, `borderColor: "#EBEBEB"`, `hoverEffect: true`. `states.selected` : `color: "#FFF0F3"`, `borderWidth: 1`, `borderColor: "#FF385C"`.
- **Pastilles (`SuperIndicator`)** : capsules accueillantes (`radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4`), ex. `"Superhôte"` ou `"Confirmé"` sur fond `#F7F7F7` / bordure `#DDDDDD` avec texte `#222222`, ou `#EBF8EC` / texte `#006904`.

## 5. Layout Principles
- **Respiration généreuse** : utiliser l'échelle `4, 8, 12, 16, 20, 24`. `styles["background"].padding` reste à `0` ; privilégier `padding: 16` ou `20` et `spacing: 16` dans `zoneFlows` pour éviter toute sensation d'entassement administratif.
- **Rayons concentriques harmonieux** : cartes principales à `radius: 16` (`padding: 20`), cartes de lignes à `radius: 12`, boutons et contrôles internes à `radius: 10`.
- **Calibrage Desktop des collections** : `ListView` riche (titre + localisation + tarif aligné à droite) à `itemExtent: 60`–`64` (`spacing: 8`), `SuperTable` aérée à `headerRowHeight: 40` et `rowHeight: 44`.

## 6. Depth & Elevation
Basé sur `designSystem: "material"`, le relief reste léger et solaire : sur le fond `#FFFFFF`, la structure naît de l'alternance entre surfaces `#F7F7F7` et cartes `#FFFFFF` entourées de `1px #DDDDDD`, complétée par une ombre douce (`elevation: 1` ou `2`, `shadowOpacity: 0.06`–`0.08`) sur la carte de synthèse ou de réservation principale.

## 7. Do's and Don'ts
- **Do** : Garder `#FF385C` rare et précieux : un seul bouton corail primaire par écran maximise son impact commercial.
- **Do** : Utiliser des bordures `#222222` sur fond blanc pour les actions secondaires importantes (`variant: "outlined"`).
- **Do** : Aérer l'intérieur des cartes avec `padding: 20` et un espacement interne de `12px` entre groupes de champs.
- **Do** : Soigner `emptyText` avec une formulation conviviale en français (ex. `"Aucune réservation prévue sur ces dates"`).
- **Don't** : Ne jamais peindre des panneaux entiers en rose/corail `#FF385C`, ce qui fatiguerait immédiatement la lecture.
- **Don't** : Ne jamais descendre sous `12px` pour les textes informatifs ou les prix secondaires.
- **Don't** : Ne jamais résumer une fiche logement ou réservation dans un bloc `textarea` multiligne fourre-tout.
- **Don't** : Ne jamais placer une `Card` à l'intérieur du `template` d'une `ListView`.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail Catalogue & Réservations** : `west: true`, `westSize: 340`, `resizeSides: true`, `autoSides: []`. Le volet `west` regroupe la barre de filtres en `north` (`autoSides: ["north"]`) et la liste des annonces/dossiers en `center` (`expandSlots: true`), tandis que la fiche détaillée occupe `center` du `mainLayout`.
- **En-tête Synthèse / KPI** : bande `north` de 3 à 4 cartes `#F7F7F7` bordées `#DDDDDD` (`northSize: 112`, `zoneAxes.north: "row"`, `spacing: 16`, `expandSlots: true`) présentant taux d'occupation, panier moyen et avis.
- **Formulaire d'édition d'offre** : centré et borné à `maxWidth: "760px"`, champs courts groupés par deux en `row` (`spacing: 12`), `scrollable: true` et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "light",
  "accent": "#FF385C",
  "components": {
    "title-main": {
      "type": "value",
      "text": "Séjours & Réservations",
      "fontFamily": "Plus Jakarta Sans",
      "fontSize": 24,
      "fontWeight": "semibold",
      "color": "#222222"
    },
    "cta-primary": {
      "type": "action",
      "variant": "filled",
      "label": "Réserver",
      "fontFamily": "Plus Jakarta Sans",
      "fontSize": 14,
      "fontWeight": "semibold",
      "backgroundColor": "#FF385C",
      "color": "#FFFFFF",
      "iconColor": "#FFFFFF",
      "radius": 10,
      "horizontalPadding": 18,
      "verticalPadding": 12
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#F7F7F7",
      "radius": 16,
      "padding": 20,
      "borderWidth": 1,
      "borderColor": "#DDDDDD",
      "elevation": 1,
      "shadowOpacity": 0.06
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 12,
      "padding": 12,
      "borderWidth": 1,
      "borderColor": "#EBEBEB",
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#FFF0F3",
            "borderWidth": 1,
            "borderColor": "#FF385C"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
