---
name: "Apple Studio"
slug: "apple"
category: "design-creative"
tagline: "Clarté éditoriale minimaliste, grilles bento aériennes et précision optique de studio."
description: "Langage visuel lumineux reposant sur un canevas gris perle #F5F5F7, des cartes bento blanc pur #FFFFFF à grands rayons continus et une hiérarchie typographique ciselée. Idéal pour les suites créatives, tableaux de bord matériels, catalogues premium et applications de productivité Desktop."
mode: "light"
accent: "#0071E3"
canvasColor: "#F5F5F7"
surfaceColor: "#FFFFFF"
textColor: "#1D1D1F"
mutedTextColor: "#6E6E73"
borderColor: "#E5E5EA"
cardRadius: 18
surfaceSystem: "material"
fontFamily: "Segoe UI"
---

# Apple Studio — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
L'atmosphère **Apple Studio** privilégie le calme visuel, la déférence envers le contenu et une respiration spatiale généreuse. Le canevas gris froid ultra-clair (`#F5F5F7`) sert de socle silencieux sur lequel se détachent des modules bento blanc pur (`#FFFFFF`) aux angles amples (`radius: 18`), sans séparateurs superflus. L'œil est guidé par le contraste net de l'encre quasi-noire (`#1D1D1F`), le gris secondaire équilibré (`#6E6E73`) et des touches chirurgicales de bleu système (`#0071E3`) réservées aux actions décisives et à l'état sélectionné.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas global** | `#F5F5F7` | `styles["background"].color` (padding `0`) |
| **Surface Bento / Carte** | `#FFFFFF` | `styles["<cardId>"].color`, panneaux principaux et fiches |
| **Surface secondaire / Champ** | `#F2F2F7` | Sous-conteneurs, fonds de `SuperValue` en saisie, barre de recherche |
| **Encre primaire** | `#1D1D1F` | Titres majeurs, valeurs KPI, libellés actifs (`SuperValue.color`) |
| **Encre secondaire (Muted)** | `#6E6E73` | Métadonnées, sous-titres, légendes et en-têtes de colonnes |
| **Accent primaire (System Blue)** | `#0071E3` | `accent` racine, CTA `SuperAction` primaire, bordure de sélection |
| **Sélection douce** | `#E8F2FF` | Fond `states.selected` des lignes `ListView` / `TreeView` |
| **Filet structurel** | `#E5E5EA` | `borderColor` subtil (`1px`) des cartes secondaires et séparateurs |
| **Statut positif / Alerte / Erreur** | `#248A3D` / `#B25000` / `#D70015` | Pastilles `SuperIndicator` sur fonds pastel `#E8F8EC` / `#FFF4E5` / `#FFECEE` |

## 3. Typography Rules
Sur Desktop, associer **`"Segoe UI"`** et **`"Inter"`** (sans-serif néo-grotesques à neutralité optique exemplaire), sans empattement et avec un crénage serré sur les grands titres (`letterSpacing: -0.4`). Limiter chaque carte à 3 tailles distinctes maximum.

| Niveau `SuperValue` | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Display / KPI Studio** | `"Segoe UI"` / `"Inter"` | `24`–`26` | `"semibold"` | `#1D1D1F` | Titre de vue principale, métrique phare d'une tuile bento |
| **2. Section / En-tête Carte** | `"Segoe UI"` / `"Inter"` | `17` | `"semibold"` | `#1D1D1F` | Titre de `Card`, d'`ApplicationBar` ou de panneau maître |
| **3. Corps / Donnée métier** | `"Segoe UI"` / `"Inter"` | `13`–`14` | `"normal"` (`"medium"` en titre de ligne) | `#1D1D1F` | Champs atomiques (`label` + `text`), cellules `SuperTable` |
| **4. Légende / Métadonnée** | `"Segoe UI"` / `"Inter"` | `11`–`12` | `"normal"` | `#6E6E73` | Horodatages, unités, compteurs secondaires, texte d'aide |

## 4. Component Stylings
- **Cartes Bento (`Card` / `IterableContent`)** : `designSystem: "material"`, `color: "#FFFFFF"`, `radius: 18`, `padding: 20`, `borderWidth: 1`, `borderColor: "#E5E5EA"`, `elevation: 1`, `shadowOpacity: 0.06`. Aucune imbrication de carte blanche dans une autre carte blanche.
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : un seul par vue, `fontFamily: "Segoe UI"`, `backgroundColor: "#0071E3"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AA garanti), `radius: 10` (ou capsule `99` pour une action d'appel isolée), `fontWeight: "medium"`, `horizontalPadding: 16`, `verticalPadding: 10`.
  - *Secondaire (`variant: "tonal"` ou `"outlined"`)* : `backgroundColor: "#F2F2F7"`, `color: "#1D1D1F"`, `iconColor: "#1D1D1F"`, `borderWidth: 0`, `radius: 10`.
- **Champs & Valeurs (`SuperValue`)** : en lecture, utiliser un `SuperValue` atomique par attribut (`label` + `text` / `binding`). En saisie (`mode: "input"`), rayons `10`, labels concis au-dessus et `variant: "segmented"` pour 2 à 4 choix exclusifs.
- **Lignes de collection (`<listId>:item` & `SuperTable`)** : `color: "#FFFFFF"` (ou `"#00000000"` dans un panneau déjà blanc), `radius: 10`, `padding: 12`, `hoverEffect: true`. Sélection `states.selected` : `color: "#E8F2FF"`, `borderWidth: 1`, `borderColor: "#0071E3"`.
- **Pastilles d'état (`SuperIndicator`)** : format capsule (`radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4`), fond teinté doux (`#E8F2FF`) associé à un texte/icône saturé foncé (`#005BB5`) pour maintenir un contraste AA net.

## 5. Layout Principles
- **Échelle d'espacement stricte** : utiliser uniquement `4, 8, 12, 16, 20, 24`. `styles["background"].padding` reste impérativement à `0` ; appliquer `padding: 16` et `spacing: 16` sur `zoneFlows` du `mainLayout` pour créer la grille bento respirante.
- **Loi de proximité & Rayons concentriques** : une carte parente à `radius: 18` et `padding: 20` accueille des contrôles internes à `radius: 10` et `spacing: 12` (`padding >= spacing` obligatoire).
- **Calibrage Desktop des collections** : `ListView` à `itemExtent: 52`–`60` (`spacing: 4`), `SuperTable` à `headerRowHeight: 38` et `rowHeight: 40` avec alignement `"end"` sur les montants et compteurs, `TreeView` latéral à `rowHeight: 34` et `indent: 18`.

## 6. Depth & Elevation
Le système repose exclusivement sur `designSystem: "material"` (ne pas activer `liquidGlass` ni `neumorphism` par défaut afin de préserver la netteté typographique sur l'ensemble de l'écran). La profondeur provient avant tout du saut de luminance entre le canevas `#F5F5F7` et les surfaces `#FFFFFF`, soutenu par une micro-ombre diffuse (`elevation: 1`, `shadowOpacity: 0.06`) et un filet capillaire `#E5E5EA` (`borderWidth: 1`).

## 7. Do's and Don'ts
- **Do** : Laisser au moins `16px` d'écart entre les tuiles bento pour laisser apparaître le canevas `#F5F5F7`.
- **Do** : Réserver `#0071E3` au seul CTA primaire de la vue, aux liens d'action et au marqueur de sélection actif.
- **Do** : Utiliser des contrôles segmentés (`variant: "segmented"`) pour basculer élégamment entre vues ou périodes courtes.
- **Do** : Aligner rigoureusement les chiffres et montants à droite (`textAlign: "end"`) dans les listes et tableaux.
- **Don't** : Ne jamais empiler des ombres lourdes (`elevation > 2` ou `shadowOpacity > 0.10`) qui salissent le gris perle.
- **Don't** : Ne jamais placer plusieurs boutons `filled` bleus côte à côte ni colorier l'arrière-plan entier des cartes KPI en couleurs vives.
- **Don't** : Ne jamais imbriquer de `"registry:Card"` dans `list.template.placements` (utiliser directement `<listId>:item`).
- **Don't** : Ne jamais concaténer libellé et valeur dans un même texte libre ou `textarea` de résumé.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Explorateur, Catalogue, Réglages)** : `west: true`, `westSize: 300` à `320`, `resizeSides: true`, `autoSides: []` (jamais `"west"` dans `autoSides`). Le volet `west` agit comme une barre latérale claire menant à une fiche centrale étirée (`expandSlots: true`).
- **Bandeau KPI supérieur** : en zone `north` (`zoneAxes.north: "row"`, `spacing: 16`, `expandSlots: true`), aligner 3 ou 4 tuiles bento blanches de hauteur homogène (`northSize: 112`).
- **Formulaires & Préférences** : centrer une carte formulaire bornée (`slotSizeConstraints.<cardId>.maxWidth: "720px"`), `scrollable: true` sur la zone feuille et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "light",
  "accent": "#0071E3",
  "components": {
    "title-studio": {
      "type": "value",
      "text": "Vue d'ensemble Studio",
      "fontFamily": "Segoe UI",
      "fontSize": 25,
      "fontWeight": "semibold",
      "letterSpacing": -0.4,
      "color": "#1D1D1F"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#F5F5F7",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 18,
      "padding": 20,
      "borderWidth": 1,
      "borderColor": "#E5E5EA",
      "elevation": 1,
      "shadowOpacity": 0.06
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 10,
      "padding": 12,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#E8F2FF",
            "borderWidth": 1,
            "borderColor": "#0071E3"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
