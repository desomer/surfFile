---
name: "Soft Neumorphism"
slug: "neumorphic-soft"
category: "special-retro"
tagline: "Surfaces tactiles extrudées dans la masse #E6E9EF, double ombre douce et indigo #5B67CA."
description: "Interface tactile sculptée utilisant le moteur natif designSystem: \"neumorphism\" où cartes et canevas partagent la même matière #E6E9EF façonnée par un couple d'ombres claire et sombre. Idéal pour les tableaux de commande domotiques, pupitres audio/média, outils bien-être et cockpits d'instruments Desktop."
mode: "light"
accent: "#5B67CA"
canvasColor: "#E6E9EF"
surfaceColor: "#E6E9EF"
textColor: "#2D3748"
mutedTextColor: "#718096"
borderColor: "#D1D9E6"
cardRadius: 20
surfaceSystem: "neumorphism"
fontFamily: "Nunito"
---

# Soft Neumorphism — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
Le style **Soft Neumorphism** transforme l'écran en un pupitre physique moulé d'une seule pièce dans un polymère gris-bleuté satiné (`#E6E9EF`). Ici, les cartes ne sont pas posées *sur* le fond avec une couleur étrangère : elles **partagent exactement la couleur `#E6E9EF` du canevas** afin que le moteur `designSystem: "neumorphism"` de `super_container_layout` sculpte l'extrusion grâce à un halo lumineux supérieur-gauche et une ombre douce inférieure-droite. Pour préserver une ergonomie irréprochable, l'ardoise foncée `#2D3748` et l'indigo velouté `#5B67CA` apportent la netteté focale qui manque souvent au neumorphisme pur.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Matière de base (Canvas)** | `#E6E9EF` | `styles["background"].color` (padding `0`) |
| **Surface extrudée (Carte)** | `#E6E9EF` | `styles["<cardId>"].color` identique au canevas pour l'extrusion |
| **Creux / Surface sélectionnée** | `#DCE1EA` | Fond pressé / sélectionné des items `ListView` et sous-zones |
| **Encre ardoise primaire** | `#2D3748` | Titres, compteurs KPI, libellés principaux (`SuperValue`) |
| **Encre ardoise douce (Muted)** | `#718096` | Légendes, unités, sous-titres et métadonnées secondaires |
| **Accent Indigo tactile** | `#5B67CA` | `accent` racine, CTA primaire `SuperAction`, bordure d'item sélectionné |
| **Biseau subtil** | `#D1D9E6` | `borderColor` optionnel (`1px`) pour sécuriser la lecture des lignes |
| **Statuts (Actif / Veille / Alerte)** | `#2F855A` / `#C05621` / `#C53030` | `SuperIndicator` sur pastilles pastel `#DEF7EC` / `#FEEBC8` / `#FED7D7` |

## 3. Typography Rules
Utiliser **`"Nunito"`** (sans-serif humaniste aux terminaisons douces et arrondies qui épouse naturellement les rayons `20px` du relief neumorphique, avec repli `"Segoe UI"`) dans des graisses affirmées (`"semibold"` / `"bold"`) en gris ardoise `#2D3748` plutôt qu'en noir brutal `#000000`, ce qui préserve la douceur minérale de la matière `#E6E9EF` tout en garantissant un excellent contraste AA.

| Niveau `SuperValue` | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Indicateur / Titre Pupitre** | `"Nunito"` | `22`–`26` | `"bold"` | `#2D3748` | Mesure centrale (température, niveau, KPI majeur), titre de vue |
| **2. Titre de Module / Carte** | `"Nunito"` | `16`–`18` | `"semibold"` | `#2D3748` | En-tête d'un module extrudé ou d'un panneau de commande |
| **3. Valeur / Paramètre / Ligne** | `"Nunito"` | `13`–`14` | `"medium"` (`"normal"` en texte) | `#2D3748` | Attributs atomiques, contrôles `switch`/`slider`, lignes `ListView` |
| **4. Unité / Sous-titre / Aide** | `"Nunito"` | `11`–`12` | `"normal"` | `#718096` | Unités physiques, horodatages, états secondaires |

## 4. Component Stylings
- **Modules extrudés (`Card`)** : `designSystem: "neumorphism"`, **`color: "#E6E9EF"`** (impératif : même teinte que `background`), `radius: 20`, `padding: 20` ou `24`, `borderWidth: 0`, `elevation: 6`, `shadowOpacity: 0.45`.
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : le bouton d'action principal doit trancher franchement avec `fontFamily: "Nunito"`, `backgroundColor: "#5B67CA"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AA verrouillé), `radius: 14`, `fontWeight: "semibold"`, `horizontalPadding: 18`, `verticalPadding: 12`.
  - *Secondaire tactile (`variant: "tonal"` ou `"outlined"`)* : `fontFamily: "Nunito"`, `backgroundColor: "#E6E9EF"`, `borderColor: "#D1D9E6"`, `borderWidth: 1`, `color: "#2D3748"`, `iconColor: "#5B67CA"`, `radius: 14`.
- **Contrôles & Champs (`SuperValue`)** : privilégier les interrupteurs `switch`, curseurs `slider` et sélecteurs `segmented` qui s'intègrent naturellement à l'esprit pupitre ; 1 `SuperValue` atomique par mesure.
- **Lignes de collection (`<listId>:item`)** : éviter d'extruder lourdement chaque ligne d'une longue liste ! Utiliser un relief léger ou plat (`color: "#E6E9EF"`, `radius: 12`, `padding: 12`, `borderWidth: 1`, `borderColor: "#D1D9E6"`, `elevation: 0`, `hoverEffect: true`). `states.selected` : effet pressé/actif avec `color: "#DCE1EA"`, `borderWidth: 1`, `borderColor: "#5B67CA"`.
- **Pastilles (`SuperIndicator`)** : `radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4`, ex. mode actif `backgroundColor: "#E0E4FA"`, `color: "#3C469E"`, `iconColor: "#3C469E"`.

## 5. Layout Principles
- **Marges généreuses obligatoires pour les ombres** : l'extrusion neumorphique (`elevation: 6`) projette un halo autour de chaque carte. Garder `styles["background"].padding: 0`, mais imposer **`zoneFlows.*.padding: 20` ou `24`** et **`spacing: 20`** entre cartes sœurs afin que leurs doubles ombres ne se télescopent pas et ne soient pas rognées aux bords.
- **Rayons concentriques doux** : modules parents à `radius: 20` (`padding: 20`–`24`), sous-éléments et boutons à `radius: 12`–`14`.
- **Collections respirantes** : `ListView` à `itemExtent: 56`–`62` (`spacing: 8`), `SuperTable` épurée à `headerRowHeight: 40` et `rowHeight: 42`.

## 6. Depth & Elevation
Ce système active explicitement **`designSystem: "neumorphism"`** sur l'ensemble des surfaces principales (`elevation: 6`, `shadowOpacity: 0.45`). Ne jamais mélanger `liquidGlass` ou `neon` sur le même écran, et limiter l'extrusion forte (`elevation: 6`) aux cartes de premier niveau : à l'intérieur d'une carte déjà extrudée, utiliser des éléments calmes (`elevation: 0` et filet `#D1D9E6`) pour éviter l'effet « coussins empilés ».

## 7. Do's and Don'ts
- **Do** : Attribuer exactement `#E6E9EF` à la fois au `background` et aux cartes `neumorphism` pour une extrusion physique crédible.
- **Do** : Prévoir `spacing: 20` et `padding: 20` autour des cartes extrudées pour laisser respirer leurs halos clair/sombre.
- **Do** : Colorer l'unique CTA primaire en indigo `#5B67CA` (`color: "#FFFFFF"`) afin que l'action principale saute aux yeux.
- **Do** : Marquer clairement l'élément sélectionné d'une liste avec un contour `#5B67CA` (`1px`) et un fond `#DCE1EA`.
- **Don't** : Ne jamais mettre `#FFFFFF` sur une carte `neumorphism` posée sur `#E6E9EF` (cela brise l'illusion d'extrusion).
- **Don't** : Ne jamais imbriquer une carte neumorphique `elevation: 6` dans une autre carte neumorphique `elevation: 6`.
- **Don't** : Ne jamais utiliser de gris pâle illisible (`#A0AEC0`) pour du texte porteur d'information.
- **Don't** : Ne jamais coller deux cartes `neumorphism` à `spacing: 4` ou `8` (leurs ombres se chevaucheraient).

## 8. Responsive & Desktop Ergonomics
- **Pupitre Maître / Détail** : `west: true`, `westSize: 320` à `340`, `resizeSides: true`, `autoSides: []`, avec `paddingInsets: [20, 10, 20, 20]` en `west` et `padding: 20` en `center` pour préserver le halo des panneaux.
- **Bandeau de capteurs / KPI** : zone `north` (`northSize: 124`, `zoneAxes.north: "row"`, `spacing: 20`, `paddingInsets: [20, 20, 20, 8]`, `expandSlots: true`) accueillant 3 ou 4 tuiles tactiles `#E6E9EF`.
- **Panneau de réglages** : carte centrale bornée à `maxWidth: "740px"`, `scrollable: true` et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "light",
  "accent": "#5B67CA",
  "components": {
    "title-console": {
      "type": "value",
      "text": "Climat & Ambiance",
      "fontFamily": "Nunito",
      "fontSize": 24,
      "fontWeight": "bold",
      "color": "#2D3748"
    },
    "cta-activate": {
      "type": "action",
      "variant": "filled",
      "label": "Activer le mode confort",
      "fontFamily": "Nunito",
      "fontSize": 14,
      "fontWeight": "semibold",
      "backgroundColor": "#5B67CA",
      "color": "#FFFFFF",
      "iconColor": "#FFFFFF",
      "radius": 14,
      "horizontalPadding": 18,
      "verticalPadding": 12
    }
  },
  "styles": {
    "background": {
      "designSystem": "neumorphism",
      "color": "#E6E9EF",
      "padding": 0
    },
    "card-main": {
      "designSystem": "neumorphism",
      "color": "#E6E9EF",
      "radius": 20,
      "padding": 20,
      "borderWidth": 0,
      "elevation": 6,
      "shadowOpacity": 0.45
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#E6E9EF",
      "radius": 12,
      "padding": 12,
      "borderWidth": 1,
      "borderColor": "#D1D9E6",
      "elevation": 0,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#DCE1EA",
            "borderWidth": 1,
            "borderColor": "#5B67CA"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
