---
name: "Vercel Geist"
slug: "vercel"
category: "developer-tools"
tagline: "Rigueur OLED #000000 absolue, grille architecturale 1px #262626 et contraste blanc chirurgical"
description: "Système visuel sombre minimaliste d'inspiration suisse combinant un noir pur #000000, des panneaux #0A0A0A découpés au rasoir par des bordures #262626, des CTA monochromes #EDEDED et des accents bleus #0070F3 de télémétrie. Idéal pour les consoles cloud, pipelines CI/CD, déploiements edge et tableaux de bord d'infrastructure."
mode: "dark"
accent: "#0070F3"
canvasColor: "#000000"
surfaceColor: "#0A0A0A"
textColor: "#EDEDED"
mutedTextColor: "#888888"
borderColor: "#262626"
cardRadius: 6
surfaceSystem: "material"
fontFamily: "Geist"
---

# Vercel Geist — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette esthétique incarne l'**ingénierie d'infrastructure à l'état pur** : géométrique, radicalement dépouillée, haute précision et sans artifice. Le canevas noir OLED absolu (`#000000`) et les panneaux carbone quasi-noirs (`#0A0A0A`) forment un treillis architectural tendu par des filets `1px` gris neutre (`#262626`) et des angles vifs (`radius: 6`). L'action primaire adopte un contraste monochrome inversé saisissant (bouton blanc `#EDEDED`, texte noir `#000000`), laissant le bleu électrique `#0070F3` briller sur les indicateurs de déploiement, liens techniques et états sélectionnés.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les consoles cloud et systèmes typographiques suisses modernes, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#000000` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#0A0A0A` | `styles["<cardId>"].color` (panneaux de métriques, logs, domaines) |
| **Elevated / Secondary Surface** | `#111111` | En-têtes de tableaux, barres de filtres, `tabBarStyle`, champs `input` |
| **Primary Text** | `#EDEDED` | `SuperValue` titres, métriques clés, noms de projets |
| **Muted / Secondary Text** | `#888888` | `SuperValue` hashes Git, latences secondaires, horodatages |
| **Hairline / Border** | `#262626` | `borderColor` (`borderWidth: 1`) et traits `SuperSeparator` |
| **Brand Accent + On-Accent** | `#0070F3` / `#FFFFFF` | Racine `"accent"`, états actifs, liens et indicateurs réseau |
| **Stark Primary CTA** | `#EDEDED` / `#000000` | `SuperAction` primaire `"filled"` (`backgroundColor: "#EDEDED"`, `color: "#000000"`) |
| **Selected Row State** | `#111927` | `styles["<listId>:item"].states.selected.style.color` (bordure `#0070F3`) |
| **Semantic Success** | `#50E3C2` | `SuperIndicator` Ready / Production (fond `#06241E`, texte `#50E3C2`) |
| **Semantic Warning** | `#F5A623` | `SuperIndicator` Building / Queued (fond `#291B05`, texte `#F5A623`) |
| **Semantic Error** | `#EE0000` | `SuperIndicator` Failed / Error 500 (fond `#2A0707`, texte `#FF6166`) |

## 3. Typography Rules
- **Familles Desktop signature** : **`"Geist"`** sur l'ensemble des titres, libellés d'interface et cartes ; **`"Geist Mono"`** obligatoire sur les identifiants de déploiement (`dpl_8f92a`), SHA de commits (`a3f9c12`), latences (`42ms`), variables d'environnement, codes HTTP et pastilles `SuperIndicator`.
- **Tension typographique** : approche négative marquée (`letterSpacing: -0.5`) sur les grands KPI et titres d'écran en `"Geist"`.

| Niveau (`SuperValue`) | `fontSize` | `fontWeight` | `color` | Famille conseillée | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `24` | `"semibold"` | `#EDEDED` | `"Geist"` / `"Geist Mono"` | Titre projet (`"Geist"`) ou métrique `38ms` (`"Geist Mono"`) |
| **2. Section / Card Title** | `15` | `"semibold"` | `#EDEDED` | `"Geist"` | En-tête de carte (`Production Deployment`) |
| **3. Body / Field Value** | `13` | `"normal"` | `#EDEDED` | `"Geist"` | Domaine, branche, libellé de carte |
| **4. Label / Mono Metadata** | `12` | `"normal"` | `#888888` | `"Geist Mono"` | ID `dpl_8f92a`, SHA, latence `42ms`, variable d'env. |

## 4. Component Stylings
- **Cards & Grid Panels (`Card`)** : `designSystem: "material"`, `color: "#0A0A0A"`, `radius: 6`, `borderWidth: 1`, `borderColor: "#262626"`, `elevation: 0`, `padding: 16` (titres et libellés internes en `"Geist"`).
- **Boutons (`SuperAction`)** :
  - *Primaire monochrome haute visibilité* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Geist"`, `backgroundColor: "#EDEDED"`, `color: "#000000"`, `iconColor: "#000000"`, `radius: 6`, `fontSize: 13`, `fontWeight: "medium"`, `horizontalPadding: 14`, `verticalPadding: 8` (contraste AAA 18:1).
  - *Secondaire* : `variant: "outlined"`, `fontFamily: "Geist"`, `backgroundColor: "#0A0A0A"`, `borderColor: "#262626"`, `borderWidth: 1`, `color: "#EDEDED"`, `iconColor: "#888888"`, `radius: 6`.
  - *Action Déploiement / Info* : `variant: "tonal"` ou `"outlined"`, `fontFamily: "Geist"`, `borderColor: "#0070F3"`, `color: "#3291FF"`, `iconColor: "#3291FF"`.
  - *Icône compacte* : `variant: "icon"`, `iconColor: "#888888"`, `tooltip` explicite.
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : `field.fillColor: "#000000"`, `field.borderColor: "#262626"`, `field.radius: 6`, `color: "#EDEDED"`, `fontFamily: "Geist Mono"` pour les clés d'API, URLs et variables d'environnement (`"Geist"` pour les champs éditoriaux).
- **Lignes de déploiement (`<listId>:item` & `Table`)** : `color: "#00000000"`, `radius: 6`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#141414"`. Sélection `states.selected` en `#111927` avec bordure `1px` `#0070F3`.
- **Indicateurs d'état (`SuperIndicator`)** : pastilles techniques compactes (`iconSize: 12`, `fontSize: 11`, `fontFamily: "Geist Mono"`, `radius: 999`, `borderWidth: 1`, `horizontalPadding: 8`, `verticalPadding: 2`).

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding: 0`. Espacement sec et architectural entre panneaux (`spacing: 12`, `padding: 16`).
- **Rayons concentriques tendus** : Panneau `radius: 6` $\rightarrow$ Champ / Bouton / Ligne `radius: 4` ou `6` (jamais d'arrondis mous `16px+`).
- **Calibrage Desktop** : `ListView` de builds avec `itemExtent: 44` à `52`, `spacing: 4`. `SuperTable` de logs/domaines avec `headerRowHeight: 34` et `rowHeight: 36`.

## 6. Depth & Elevation
- **Zéro élévation diffuse** : `designSystem: "material"` et `elevation: 0` sur tout l'écran. Sur fond `#000000`, les ombres portées noires sont invisibles et inutiles : toute la structure provient exclusivement des filets `#262626` et du contraste `#000000` / `#0A0A0A` / `#111111`.
- **Survol précis** : privilégier un éclaircissement net du fond (`#141414`) ou de la bordure (`#404040` via `states.hover`) plutôt qu'un soulèvement 3D.

## 7. Do's and Don'ts
- **Do** : Styliser le bouton d'action principal en blanc franc `#EDEDED` avec texte et icône `#000000`.
- **Do** : Appliquer `"Geist Mono"` sur tous les identifiants `dpl_*`, hashes SHA, durées millisecondes (`42ms`), variables d'environnement et pastilles `SuperIndicator`.
- **Do** : Garder une géométrie stricte à `radius: 6` et `borderWidth: 1` (`#262626`).
- **Do** : Aligner les métriques numériques et temps d'exécution à droite (`textAlign: "end"`).
- **Don't** : Ne jamais teinter les gris neutres (`#0A0A0A`, `#262626`, `#888888`) avec du violet ou du marron.
- **Don't** : Ne jamais oublier `color: "#000000"` sur un bouton `#EDEDED` (texte blanc sur bouton blanc = illisible).
- **Don't** : Ne jamais utiliser de coins très arrondis (`radius >= 12`) ni d'effets `neumorphism`.
- **Don't** : Ne jamais surcharger les cartes KPI avec des icônes décoratives géantes.

## 8. Responsive & Desktop Ergonomics
- **Console Projet + Inspecteur de Build** : `mainLayout` avec liste des déploiements/services en `west` (`westSize: 320`, `resizeSides: true`, `"autoSides": []`) et journal/métriques détaillées en `center` (`expandSlots: true`).
- **Grille de télémétrie Edge** : rangée `north` de 4 compteurs KPI monochromes (`northSize: 96`, `zoneAxes.north: "row"`, `spacing: 12`) suivie en `center` d'un graphique `Chart` sobre (`#0070F3` / `#50E3C2`) et d'une `SuperTable` d'événements.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "dark",
  "accent": "#0070F3",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#000000",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#0A0A0A",
      "radius": 6,
      "borderWidth": 1,
      "borderColor": "#262626",
      "elevation": 0,
      "padding": 16
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 6,
      "paddingInsets": [6, 10, 6, 10],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#141414",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#111927",
            "borderWidth": 1,
            "borderColor": "#0070F3"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "project-heading": {
      "type": "value",
      "text": "Production Deployment",
      "fontFamily": "Geist",
      "fontSize": 24,
      "fontWeight": "semibold",
      "letterSpacing": -0.5,
      "color": "#EDEDED"
    },
    "deploy-meta": {
      "type": "value",
      "label": "Déploiement",
      "text": "dpl_8f92a · 42ms",
      "fontFamily": "Geist Mono",
      "fontSize": 12,
      "color": "#888888"
    },
    "pill-ready": {
      "type": "indicator",
      "icon": "check_circle",
      "label": "READY · 42ms",
      "fontFamily": "Geist Mono",
      "fontSize": 11,
      "iconSize": 12,
      "color": "#50E3C2",
      "iconColor": "#50E3C2",
      "backgroundColor": "#06241E",
      "borderColor": "#50E3C2",
      "borderWidth": 1,
      "radius": 999,
      "horizontalPadding": 8,
      "verticalPadding": 2
    },
    "btn-deploy": {
      "type": "action",
      "kind": "textAndIcon",
      "variant": "filled",
      "icon": "cloud_upload",
      "label": "Redéployer",
      "fontFamily": "Geist",
      "fontSize": 13,
      "fontWeight": "medium",
      "backgroundColor": "#EDEDED",
      "color": "#000000",
      "iconColor": "#000000",
      "radius": 6,
      "horizontalPadding": 14,
      "verticalPadding": 8
    }
  }
}
```
