---
name: "Figma"
slug: "figma"
category: "design-creative"
tagline: "Espace de travail d'inspection précis, cloisons 1px nettes et densité créative calibrée."
description: "Système d'interface orienté outils de conception combinant un canevas neutre #F5F5F5, des panneaux latéraux blanc pur #FFFFFF cloisonnés par des filets #E6E6E6 de 1px et un bleu électrique #0D99FF de sélection. Parfait pour les éditeurs métier, inspecteurs techniques, gestionnaires d'assets et studios Desktop haute densité."
mode: "light"
accent: "#0D99FF"
canvasColor: "#F5F5F5"
surfaceColor: "#FFFFFF"
textColor: "#1E1E1E"
mutedTextColor: "#757575"
borderColor: "#E6E6E6"
cardRadius: 8
surfaceSystem: "material"
fontFamily: "Inter"
---

# Figma — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
L'esthétique **Figma** incarne l'atelier d'inspection professionnel : rapide, géométrique, sobre et sans artifice décoratif. Toute l'interface s'organise autour d'une grille utilitaire compacte où le canevas de travail `#F5F5F5` met en valeur des panneaux d'outils `#FFFFFF` délimités au pixel près par des filets continus `#E6E6E6` (`1px`) et des rayons serrés (`radius: 8`). La couleur s'efface volontairement au profit du contenu étudié, ne surgissant qu'à travers le bleu vif `#0D99FF` pour signaler la sélection active, le focus clavier et l'action primaire.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas d'atelier** | `#F5F5F5` | `styles["background"].color` (padding `0`) |
| **Panneau / Carte d'inspection** | `#FFFFFF` | `styles["<cardId>"].color`, volets `west`/`east` et fiches |
| **Champ / Contrôle au repos** | `#F5F5F5` | Fond discret de saisie, barre de filtre ou bouton tonal |
| **Texte primaire** | `#1E1E1E` | Libellés d'arborescence, valeurs de propriétés, titres (`SuperValue`) |
| **Texte secondaire (Muted)** | `#757575` | Étiquettes d'attributs, raccourcis, coordonnées, unités |
| **Accent sélection & CTA** | `#0D99FF` | `accent` racine, bouton primaire `SuperAction`, contour de focus |
| **Teinte de sélection active** | `#E5F4FF` | Fond `states.selected` des calques, lignes de liste et onglets |
| **Cloison / Filet 1px** | `#E6E6E6` | `borderColor` systématique (`borderWidth: 1`) des panneaux et tables |
| **Tokens sémantiques (OK / Warn / Err)** | `#14AE5C` / `#F24822` | `SuperIndicator` (vert composant validé `#E6F9EE`, corail alerte `#FFEBE6`) |

## 3. Typography Rules
Utiliser **`"Inter"`** avec une échelle compacte (`12`–`13px` sur les lignes d'inspecteur et de calques, repli `"Segoe UI"`) pensée pour lire simultanément arborescences, tableaux et panneaux de propriétés sans défilement excessif, associée à **`"JetBrains Mono"`** pour les coordonnées (`X/Y`), dimensions, tokens et codes hexadécimaux (`#0D99FF`).

| Niveau `SuperValue` | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Titre de document / KPI** | `"Inter"` | `20`–`22` | `"semibold"` | `#1E1E1E` | Nom du projet, métrique principale d'un tableau de bord |
| **2. En-tête de panneau / Section** | `"Inter"` | `14`–`15` | `"semibold"` | `#1E1E1E` | Titre de section d'inspecteur, en-tête de `Card` ou d'onglet |
| **3. Propriété / Ligne de calque** | `"Inter"` | `12`–`13` | `"normal"` (`"medium"` si actif) | `#1E1E1E` | Lignes d'inspecteur `TreeView`/`ListView`, champs `input`, cellules `Table` |
| **4. Coordonnée / Hex / Unité** | `"JetBrains Mono"` / `"Inter"` | `11` | `"normal"` | `#757575` | Coordonnées `X/Y`, valeurs `#HEX` (`JetBrains Mono`), sous-légendes |

## 4. Component Stylings
- **Panneaux & Cartes (`Card`)** : `designSystem: "material"`, `color: "#FFFFFF"`, `radius: 8`, `padding: 12` (inspecteur compact) ou `16` (panneau central), `borderWidth: 1`, `borderColor: "#E6E6E6"`, `elevation: 0`.
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : `fontFamily: "Inter"`, `backgroundColor: "#0D99FF"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AA net), `radius: 6`, `fontSize: 12`, `fontWeight: "medium"`, `horizontalPadding: 12`, `verticalPadding: 8`.
  - *Secondaire (`variant: "outlined"`)* : `fontFamily: "Inter"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#E6E6E6"`, `borderWidth: 1`, `color: "#1E1E1E"`, `iconColor: "#1E1E1E"`, `radius: 6`.
  - *Outil d'en-tête (`kind: "icon"`, `variant: "icon"`)* : `iconColor: "#1E1E1E"`, `tooltip` explicite obligatoire.
- **Champs de propriétés (`SuperValue`)** : privilégier la compacité (`fontFamily: "Inter"`, ou `"JetBrains Mono"` sur les coordonnées et codes hexadécimaux, `fontSize: 12`, `radius: 6`), 1 `SuperValue` par attribut métier (`label` + `text`/`binding`), et `variant: "segmented"` pour les alignements ou modes d'affichage.
- **Arborescences & Listes (`<listId>:item`)** : `color: "#FFFFFF"`, `radius: 6`, `padding: 8`, `hoverEffect: true`. `states.selected` : `color: "#E5F4FF"`, `borderWidth: 1`, `borderColor: "#0D99FF"`.
- **Badges & Statuts (`SuperIndicator`)** : format pilule compacte (`radius: 6` ou `99`, `horizontalPadding: 8`, `verticalPadding: 3`), ex. badge composant publié `backgroundColor: "#E5F4FF"`, `color: "#0066CC"`, `iconColor: "#0066CC"`.

## 5. Layout Principles
- **Grille 4 / 8 px rigoureuse** : espacements `4, 8, 12, 16, 20, 24`. `styles["background"].padding` vaut `0`. Les espacements entre panneaux (`zoneFlows.*.spacing` et `padding`) sont calibrés à `8` ou `12` pour maximiser la surface utile de travail.
- **Rayons concentriques serrés** : panneau parent à `radius: 8` (`padding: 12` ou `16`), contrôles enfants, champs et items sélectionnés à `radius: 6`.
- **Collections haute densité** : `TreeView` de calques à `rowHeight: 32` et `indent: 16`, `ListView` compacte à `itemExtent: 40`–`48` (`spacing: 4`), `SuperTable` à `headerRowHeight: 34` et `rowHeight: 36`.

## 6. Depth & Elevation
L'interface est résolument **plate et architecturale** (`designSystem: "material"`, `elevation: 0` sur tous les panneaux ancrés). La hiérarchie des plans ne repose pas sur des ombres portées mais sur l'opposition franche entre le fond `#F5F5F5`, les surfaces `#FFFFFF` et les bordures continues `1px #E6E6E6`. Une légère élévation (`elevation: 2`, `shadowOpacity: 0.08`) est strictement réservée aux menus flottants ou barres d'outils détachées.

## 7. Do's and Don'ts
- **Do** : Structurer les écrans riches avec des volets latéraux compacts (`280px`–`300px`) encadrant un espace central étiré.
- **Do** : Maintenir des filets `1px #E6E6E6` nets et continus sur toutes les cartes et tables (`elevation: 0`).
- **Do** : Renseigner systématiquement un `tooltip` précis sur chaque bouton icône de barre d'outils.
- **Do** : Marquer toute sélection de ligne par le duo `#E5F4FF` (fond) + `#0D99FF` (bordure `1px`).
- **Don't** : Ne jamais utiliser de grands rayons mous (`radius > 10`) qui brisent la précision d'outil professionnel.
- **Don't** : Ne jamais gonfler les hauteurs de lignes au-delà de `52px` pour de simples listes d'éléments ou propriétés.
- **Don't** : Ne jamais multiplier les couleurs d'accentuation concurrentes hors des statuts métier réels.
- **Don't** : Ne jamais activer `autoSides` sur un volet `west` ou `east` contenant un `TreeView` ou une `ListView`.

## 8. Responsive & Desktop Ergonomics
- **Architecture Studio (Navigation `west` + Scène `center` + Inspecteur `east`)** : `westSize: 280`, `eastSize: 300`, `resizeSides: true`, `autoSides: []`, coins `nw`/`ne`/`sw`/`se` explicitement réglés sur `"row"` si une barre d'outils `north` coexiste.
- **Barre d'indicateurs KPI / Résumé** : `north` compacte (`northSize: 92`–`104`), `zoneAxes.north: "row"`, `spacing: 12`, cartes plates bordées `1px #E6E6E6`.
- **Formulaires de configuration** : regrouper les paires de valeurs courtes (ex. largeur/hauteur, début/fin) sur une ligne horizontale (`Layout` en `row`, `spacing: 8`) et borner le formulaire à `maxWidth: "720px"`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "light",
  "accent": "#0D99FF",
  "components": {
    "inspector-title": {
      "type": "value",
      "text": "Propriétés du calque",
      "fontFamily": "Inter",
      "fontSize": 13,
      "fontWeight": "semibold",
      "color": "#1E1E1E"
    },
    "prop-fill-hex": {
      "type": "value",
      "label": "Remplissage",
      "text": "#0D99FF",
      "fontFamily": "JetBrains Mono",
      "fontSize": 12,
      "color": "#1E1E1E"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#F5F5F5",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 8,
      "padding": 16,
      "borderWidth": 1,
      "borderColor": "#E6E6E6",
      "elevation": 0
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 6,
      "padding": 8,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#E5F4FF",
            "borderWidth": 1,
            "borderColor": "#0D99FF"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
