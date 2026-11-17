---
name: "Spotify"
slug: "spotify"
category: "media-retail"
tagline: "Scène média nocturne immersive, surfaces velours #181818 et énergie vert vif #1DB954."
description: "Système dark-mode riche pensé pour la découverte et la lecture de catalogues, bâti sur un fond #121212, des cartes #181818 s'éclairant en #282828 au survol et un vert emblématique #1DB954 à texte noir haute lisibilité. Idéal pour les médiathèques, studios audio/vidéo, catalogues culturels et hubs d'analytics créateurs."
mode: "dark"
accent: "#1DB954"
canvasColor: "#121212"
surfaceColor: "#181818"
textColor: "#FFFFFF"
mutedTextColor: "#B3B3B3"
borderColor: "#282828"
cardRadius: 10
surfaceSystem: "material"
fontFamily: "Plus Jakarta Sans"
---

# Spotify — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
L'univers **Spotify** plonge l'utilisateur dans une salle d'écoute feutrée où l'interface s'efface au profit des œuvres, des listes de lecture et des indicateurs d'audience. Le socle anthracite `#121212` soutient des panneaux `#181818` qui gagnent immédiatement en présence au survol (`#282828`), créant une sensation tactile fluide sans bordures agressives. La typographie blanche musclée et le vert vibrant `#1DB954` (toujours associé à une encre noire `#000000` sur les boutons pleins) donnent un rythme énergique et instantanément repérable.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Scène globale (Base)** | `#121212` | `styles["background"].color` (padding `0`) |
| **Carte / Panneau média** | `#181818` | `styles["<cardId>"].color`, panneaux bibliothèque et fiches |
| **Surface élevée / Survol** | `#282828` | `borderColor` subtil, fond `states.hover` des cartes et capsules filtres |
| **Texte primaire** | `#FFFFFF` | Titres d'albums/projets, valeurs KPI, pistes actives (`SuperValue`) |
| **Texte secondaire (Muted)** | `#B3B3B3` | Artistes, auteurs, durées, compteurs d'écoutes et légendes |
| **Accent primaire (Vibrant Green)** | `#1DB954` | `accent` racine, CTA primaire `SuperAction`, indicateur de lecture |
| **Surface sélectionnée** | `#1E3226` | Fond `states.selected` des lignes actives avec filet `#1DB954` |
| **Séparateur sombre** | `#282828` | Filet discret (`1px`) entre zones ou en-têtes de tableaux |
| **Statuts (Explicit / Live / Alerte)** | `#1DB954` / `#FFA42B` / `#E91429` | Pastilles `SuperIndicator` contrastées sur fonds sombres dédiés |

## 3. Typography Rules
Utiliser **`"Plus Jakarta Sans"`** avec des titres d'affichage et de playlists affirmés (`"bold"`, `letterSpacing: -0.4`) ainsi que sur les tables de pistes denses, complété par **`"Consolas"`** (ou **`"Inter"`**) pour les durées de pistes (`3:42`) et compteurs alignés, grâce au gris clair `#B3B3B3` nettement plus lumineux que la moyenne des thèmes sombres.

| Niveau `SuperValue` | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Titre Vedette / KPI Audience** | `"Plus Jakarta Sans"` | `24`–`26` | `"bold"` | `#FFFFFF` | Titre de playlist/collection phare, total d'écoutes ou revenus |
| **2. Section / En-tête Panneau** | `"Plus Jakarta Sans"` | `17`–`18` | `"bold"` | `#FFFFFF` | Titre de `Card` bibliothèque, de classement ou d'onglet |
| **3. Piste / Élément / Champ** | `"Plus Jakarta Sans"` | `13`–`14` | `"medium"` (`"normal"` en cellule) | `#FFFFFF` | Titre de piste/ligne, tables de titres denses, métadonnées |
| **4. Durée / Artiste / Métadonnée** | `"Consolas"` / `"Inter"` | `12` | `"normal"` | `#B3B3B3` | Durée de piste (`3:42` en `"Consolas"`), artiste ou compteur aligné `"end"` |

## 4. Component Stylings
- **Cartes & Panneaux (`Card` / `IterableContent`)** : `designSystem: "material"`, `color: "#181818"`, `radius: 10`, `padding: 16` ou `20`, `borderWidth: 1`, `borderColor: "#282828"`, `elevation: 0`. Pour les cartes cliquables, activer `states.hover` avec `color: "#282828"`.
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : **règle de contraste critique** — sur `backgroundColor: "#1DB954"`, imposer impérativement `color: "#000000"` et `iconColor: "#000000"` (jamais de texte blanc sur `#1DB954`), `fontFamily: "Plus Jakarta Sans"`, format pilule `radius: 99`, `fontWeight: "bold"`, `horizontalPadding: 20`, `verticalPadding: 10`.
  - *Secondaire (`variant: "outlined"` ou `"tonal"`)* : `fontFamily: "Plus Jakarta Sans"`, `backgroundColor: "#282828"` (ou transparent), `borderColor: "#535353"`, `borderWidth: 1`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 99`.
- **Champs & Filtres (`SuperValue`)** : utiliser `variant: "filterChip"` (capsules `#282828`) pour filtrer par genre, format ou période ; 1 `SuperValue` atomique par donnée métier.
- **Lignes de catalogue (`<listId>:item` & `SuperTable`)** : `color: "#181818"` (ou `"#00000000"` dans un panneau `#181818`), `radius: 6`, `padding: 10`, `hoverEffect: true`, `hoverColor: "#282828"`. `states.selected` : `color: "#1E3226"`, `borderWidth: 1`, `borderColor: "#1DB954"`.
- **Indicateurs (`SuperIndicator`)** : capsules `radius: 99` (`horizontalPadding: 10`, `verticalPadding: 4`), ex. statut `"En diffusion"` avec `backgroundColor: "#1DB954"`, `color: "#000000"`, `iconColor: "#000000"`.

## 5. Layout Principles
- **Grille d'espacement fluide** : valeurs `4, 8, 12, 16, 20, 24`. `styles["background"].padding` reste à `0`. Utiliser un espacement `8` ou `12` entre les grands panneaux sombres (`west` bibliothèque et `center` scène principale) à la manière des panneaux détachés modernes.
- **Rayons concentriques** : panneaux et cartes à `radius: 10` (`padding: 16`), lignes de piste internes à `radius: 6`, mais boutons d'action et puces de filtre en **capsule intégrale** (`radius: 99`).
- **Collections média Desktop** : `ListView` de pistes/médias à `itemExtent: 52`–`56` (`spacing: 4`), `SuperTable` de catalogue à `headerRowHeight: 36` et `rowHeight: 42` avec colonne titre extensible (`fillPercent: 100`) et colonne durée/compteur fixe alignée `"end"`.

## 6. Depth & Elevation
Construit sur `designSystem: "material"` avec `elevation: 0` à `2` (`shadowOpacity: 0.25` uniquement sur les cartes mises en avant), le relief s'exprime par **trois paliers sombres progressifs** : `#121212` (scène arrière) $\rightarrow$ `#181818` (panneau/carte au repos) $\rightarrow$ `#282828` (élément survolé ou contrôle actif).

## 7. Do's and Don'ts
- **Do** : Toujours associer `color: "#000000"` et `iconColor: "#000000"` à tout fond vert `#1DB954` pour garantir un contraste AA irréprochable.
- **Do** : Utiliser des rayons capsule (`radius: 99`) sur les boutons `SuperAction` et les filtres rapides.
- **Do** : Faire passer les lignes et cartes de `#181818` à `#282828` au survol pour un retour immédiat.
- **Do** : Aligner durées, nombres d'écoutes et revenus à droite (`textAlign: "end"`).
- **Don't** : Ne jamais écrire en blanc `#FFFFFF` sur un bouton plein `#1DB954` (contraste insuffisant).
- **Don't** : Ne jamais entourer chaque ligne de piste d'une bordure claire permanente qui alourdirait la liste.
- **Don't** : Ne jamais imbriquer une `Card` dans `list.template.placements`.
- **Don't** : Ne jamais utiliser `autoSides` sur la bibliothèque latérale `west` contenant une `ListView`.

## 8. Responsive & Desktop Ergonomics
- **Disposition Bibliothèque + Scène (+ Détail optionnel)** : `west: true`, `westSize: 300` à `320`, `resizeSides: true`, `autoSides: []`. La zone `west` héberge la bibliothèque filtrable ; la zone `center` (`expandSlots: true`) présente l'en-tête vedette, les KPI et la table des titres. Si une barre de contrôle/lecture `south` est présente (`southSize: 72`), régler `sw` et `se` sur `"row"`.
- **Bandeau KPI Créateur** : en `north` (`northSize: 108`, `zoneAxes.north: "row"`, `spacing: 12`, `expandSlots: true`), 3 à 4 cartes `#181818` affichant audiences, écoutes et taux de complétion.
- **Édition de métadonnées** : formulaire centré borné à `maxWidth: "720px"`, `scrollable: true` et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "dark",
  "accent": "#1DB954",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#121212",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#181818",
      "radius": 10,
      "padding": 16,
      "borderWidth": 1,
      "borderColor": "#282828",
      "elevation": 0
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#181818",
      "radius": 6,
      "padding": 10,
      "hoverEffect": true,
      "hoverColor": "#282828",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#1E3226",
            "borderWidth": 1,
            "borderColor": "#1DB954"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "playlist-title": {
      "type": "value",
      "text": "Radar des Sorties",
      "fontFamily": "Plus Jakarta Sans",
      "fontSize": 26,
      "fontWeight": "bold",
      "letterSpacing": -0.4,
      "color": "#FFFFFF"
    },
    "track-duration": {
      "type": "value",
      "text": "3:42",
      "fontFamily": "Consolas",
      "fontSize": 12,
      "textAlign": "end",
      "color": "#B3B3B3"
    },
    "btn-play": {
      "type": "action",
      "kind": "textAndIcon",
      "variant": "filled",
      "icon": "play_arrow",
      "label": "Lecture",
      "fontFamily": "Plus Jakarta Sans",
      "fontWeight": "bold",
      "backgroundColor": "#1DB954",
      "color": "#000000",
      "iconColor": "#000000",
      "radius": 99,
      "horizontalPadding": 20,
      "verticalPadding": 10
    }
  }
}
```
