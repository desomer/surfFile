---
name: "Retro Classic 98"
slug: "retro-desktop"
category: "special-retro"
tagline: "Nostalgie bureautique 1998, bureau sarcelle #008080, boîtes platine #D4D0C8 et marine #000080."
description: "Hommage néo-brutaliste et rétro aux systèmes de bureau de 1998 : fond sarcelle #008080, fenêtres gris platine #D4D0C8 à coins vifs 0px, bordures franches 2px #000000 / #808080 et barres de titre bleu marine #000080. Idéal pour les utilitaires système, gestionnaires de fichiers rétro, outils développeur nostalgiques et interfaces néo-brutalistes."
mode: "light"
accent: "#000080"
canvasColor: "#008080"
surfaceColor: "#D4D0C8"
textColor: "#000000"
mutedTextColor: "#404040"
borderColor: "#000000"
cardRadius: 0
surfaceSystem: "material"
fontFamily: "Tahoma"
---

# Retro Classic 98 — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
L'univers **Retro Classic 98** célèbre la franchise mécanique de l'informatique personnelle de la fin des années 1990, réinterprétée avec la propreté structurelle moderne de `super_container_layout`. Sur le célèbre bureau vert sarcelle `#008080`, chaque panneau se présente comme une boîte de dialogue gris platine `#D4D0C8` aux angles strictement droits (`radius: 0`), encadrée de bordures nettes (`2px #000000` ou `#808080`) et coiffée d'accents bleu marine `#000080` à texte blanc pur. Les puits de données (listes, arbres, tables et saisies) s'ouvrent en blanc franc `#FFFFFF` pour offrir une lisibilité immédiate.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Bureau classique (Canvas)** | `#008080` | `styles["background"].color` (padding `0`) |
| **Fenêtre / Boîte de dialogue** | `#D4D0C8` | `styles["<cardId>"].color`, panneaux d'outils et barres d'état |
| **Puits de données / Liste / Champ** | `#FFFFFF` | Fond des lignes de `ListView`, `SuperTable`, `TreeView` et champs |
| **Encre système primaire** | `#000000` | Texte principal, valeurs, libellés de boutons gris (`SuperValue`) |
| **Encre secondaire (Dark Gray)** | `#404040` | Légendes techniques, chemins, tailles d'octets, aides |
| **Bleu Marine Titre & Sélection** | `#000080` | `accent` racine, barre de titre `ApplicationBar`, CTA primaire et sélection |
| **Bordure cadre extérieur** | `#000000` | `borderColor` franc (`borderWidth: 2`) des fenêtres principales |
| **Biseau / Séparateur interne** | `#808080` | Bordures `1px` des sous-groupes, tables et séparateurs `SuperSeparator` |
| **Statuts rétro (OK / Alerte / Stop)** | `#006400` / `#806000` / `#A80000` | `SuperIndicator` carrés (`radius: 0`) sur fonds `#E0F2E0` / `#FFF8DC` / `#FFE4E1` |

## 3. Typography Rules
S'appuyer sur `"Tahoma"` pour l'ensemble de l'interface (signature typographique historique des boîtes de dialogue Desktop compactes) et sur `"Consolas"` pour les compteurs système, adresses, tailles de fichiers, journaux et horodatages. Aucune police décorative moderne arrondie.

| Niveau `SuperValue` | Police (`fontFamily`) | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. En-tête Fenêtre / Compteur** | `"Tahoma"` | `18`–`22` | `"bold"` | `#000000` (ou `#FFFFFF` sur bandeau `#000080`) | Titre principal de fenêtre ou KPI système majeur |
| **2. Groupe / Section de dialogue** | `"Tahoma"` | `14`–`15` | `"bold"` | `#000000` | En-tête de panneau `#D4D0C8`, titre d'onglet `SuperTab` |
| **3. Contrôle / Entrée / Cellule** | `"Tahoma"` | `12`–`13` | `"normal"` | `#000000` | Champs `SuperValue`, lignes d'explorateur, boutons |
| **4. Registre / Chemin / Statut** | `"Consolas"` | `11`–`12` | `"normal"` | `#404040` | Octets, chemins système, codes d'état, horodatages |

## 4. Component Stylings
- **Fenêtres & Panneaux (`Card`)** : `designSystem: "material"`, `color: "#D4D0C8"`, **`radius: 0`**, `padding: 12` ou `16`, `borderWidth: 2`, `borderColor: "#000000"`, `elevation: 0` (optionnel : bandeau supérieur `ApplicationBar` ou sous-conteneur d'en-tête en `backgroundColor: "#000080"`, `foregroundColor: "#FFFFFF"`).
- **Boutons (`SuperAction`)** :
  - *Primaire par défaut (`variant: "filled"`)* : bouton d'action par défaut bleu marine `backgroundColor: "#000080"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AAA), **`radius: 0`**, `borderWidth: 2`, `borderColor: "#000000"`, `fontFamily: "Tahoma"`, `fontSize: 12`, `fontWeight: "bold"`, `horizontalPadding: 16`, `verticalPadding: 8`.
  - *Bouton système classique (`variant: "outlined"`)* : `backgroundColor: "#D4D0C8"`, `borderColor: "#000000"`, `borderWidth: 1`, `color: "#000000"`, `iconColor: "#000000"`, `radius: 0`, `fontFamily: "Tahoma"`.
- **Champs & Contrôles (`SuperValue`)** : `radius: 0`, cases à cocher `checkbox` (préférées aux `switch` anachroniques dans ce thème !) et listes déroulantes `dropdown` classiques ; 1 `SuperValue` atomique par propriété.
- **Lignes d'explorateur (`<listId>:item` & `SuperTable`)** : puits blanc `#FFFFFF`, `radius: 0`, `padding: 8`, `borderWidth: 1`, `borderColor: "#D4D0C8"`, `hoverEffect: true`, `hoverColor: "#EAE8E3"`. `states.selected` : surbrillance classique bleu marine `color: "#000080"` (ou `#D6E0F5` avec bordure `2px #000080` si les `SuperValue` internes gardent un texte `#000000` fixe afin de préserver un contraste AA permanent !).
- **Pastilles système (`SuperIndicator`)** : étiquettes carrées **`radius: 0`**, `borderWidth: 1`, `borderColor: "#808080"`, `horizontalPadding: 8`, `verticalPadding: 3`, `fontFamily: "Consolas"`.

## 5. Layout Principles
- **Densité bureautique carrée** : échelle `4, 8, 12, 16, 20, 24`. `styles["background"].padding` vaut `0`, mais laisser `padding: 12` et `spacing: 12` dans `zoneFlows` du `mainLayout` afin qu'une bordure du bureau sarcelle `#008080` encadre visiblement les fenêtres `#D4D0C8`.
- **Zéro arrondi (`radius: 0`)** : appliquer `radius: 0` partout (fenêtres, onglets, boutons, champs, lignes et indicateurs).
- **Collections d'explorateur Desktop** : `TreeView` de dossiers à `rowHeight: 28`–`32` (`indent: 18`), `ListView` compacte à `itemExtent: 40`–`48` (`spacing: 2`), `SuperTable` détaillée à `headerRowHeight: 32` et `rowHeight: 32`.

## 6. Depth & Elevation
Utiliser `designSystem: "material"` avec **`elevation: 0`** (aucun flou gaussien moderne). La sensation de boîte mécanique repose sur le contraste franc entre le bureau `#008080`, le châssis platine `#D4D0C8`, les puits de données `#FFFFFF` et les bordures nettes `1px`–`2px` (`#000000` et `#808080`).

## 7. Do's and Don'ts
- **Do** : Laisser le canevas `#008080` visible dans les interstices (`12px`) autour des panneaux `#D4D0C8` pour signer immédiatement l'ambiance 98.
- **Do** : Privilégier `checkbox` et `dropdown` plutôt que des interrupteurs `switch` modernes.
- **Do** : Veiller au contraste AA des lignes sélectionnées : si le texte des `SuperValue` de la ligne est noir `#000000`, utiliser un fond sélectionné clair `#D6E0F5` bordé `2px #000080` plutôt qu'un fond `#000080` qui noierait le texte noir.
- **Do** : Aligner les boutons `"OK"` / `"Appliquer"` / `"Annuler"` horizontalement en bas à droite d'une boîte de dialogue (`mainAxisAlignment: "end"`, `spacing: 8`).
- **Don't** : Ne jamais ajouter de `radius > 0` ni de `backdropBlur` / `liquidGlass`.
- **Don't** : Ne jamais écrire du texte courant directement sur le fond sarcelle `#008080` hors d'une fenêtre `#D4D0C8`.
- **Don't** : Ne jamais imbriquer une `Card` dans `list.template.placements`.
- **Don't** : Ne jamais activer `autoSides` sur un volet d'arborescence `west` défilant.

## 8. Responsive & Desktop Ergonomics
- **Explorateur Classique à 2 volets (Arbre `west` + Liste/Détail `center`)** : `west: true`, `westSize: 280` à `300`, `resizeSides: true`, `autoSides: []`. Une barre d'état sobre peut occuper `south` (`southSize: 32`, coins `sw`/`se` en `"row"`).
- **Bandeau Compteurs Système** : zone `north` (`northSize: 96`, `zoneAxes.north: "row"`, `spacing: 12`, `expandSlots: true`) alignant 3 ou 4 boîtes `#D4D0C8` bordées `2px #000000` avec valeurs en `"Consolas"`.
- **Boîte de Propriétés / Formulaire** : fenêtre centrale bornée à `maxWidth: "680px"`, structurée par un `SuperTab` d'onglets carrés ou des sections séparées par `SuperSeparator` (`lineColor: "#808080"`), `scrollable: true` et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "light",
  "accent": "#000080",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#008080",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#D4D0C8",
      "radius": 0,
      "padding": 16,
      "borderWidth": 2,
      "borderColor": "#000000",
      "elevation": 0
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 0,
      "padding": 8,
      "borderWidth": 1,
      "borderColor": "#D4D0C8",
      "elevation": 0,
      "hoverEffect": true,
      "hoverColor": "#EAE8E3",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#D6E0F5",
            "borderWidth": 2,
            "borderColor": "#000080"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "window-title": {
      "type": "value",
      "text": "Poste de travail",
      "fontFamily": "Tahoma",
      "fontSize": 18,
      "fontWeight": "bold",
      "color": "#000000"
    },
    "status-bytes": {
      "type": "indicator",
      "icon": "storage",
      "label": "640 KB OK",
      "fontFamily": "Consolas",
      "fontSize": 11,
      "color": "#000000",
      "iconColor": "#000080",
      "backgroundColor": "#D4D0C8",
      "borderColor": "#808080",
      "borderWidth": 1,
      "radius": 0,
      "horizontalPadding": 8,
      "verticalPadding": 3
    }
  }
}
```
