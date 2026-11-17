---
name: "Linear"
slug: "linear"
category: "productivity-saas"
tagline: "Précision nocturne minimaliste, filets 1px acier et accentuation lavande chirurgicale"
description: "Langage visuel sombre haute densité fondé sur des surfaces graphite ultra-plates sans ombres lourdes, des bordures fines #23252A et une typographie géométrique resserrée. Idéal pour les outils de gestion de projets, suivis d'incidents, roadmaps produit et cockpits opérationnels rapides au clavier."
mode: "dark"
accent: "#5E6AD2"
canvasColor: "#08090A"
surfaceColor: "#111215"
textColor: "#F7F8F8"
mutedTextColor: "#8A8F98"
borderColor: "#23252A"
cardRadius: 8
surfaceSystem: "material"
fontFamily: "Inter"
---

# Linear — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette direction esthétique incarne le **craft logiciel nocturne ultra-minimaliste** : calme, véloce, silencieux et focalisé sur le flux de travail. Le canevas carbone profond (`#08090A`) s'efface derrière des panneaux graphite (`#111215`) délimités uniquement par des filets `1px` (`#23252A`), sans ombres portées diffuses ni ornements superflus. La couleur lavande signature (`#5E6AD2`) est utilisée avec parcimonie pour signaler l'action primaire et l'élément actif.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par l'esthétique des outils de productivité modernes, formulée spécifiquement pour le moteur `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#08090A` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#111215` | `styles["<cardId>"].color` (panneaux principaux, fiches détail) |
| **Elevated / Secondary Surface** | `#181A1F` | Sous-conteneurs, en-têtes d'outils, barres d'onglets (`tabBarStyle`) |
| **Primary Text** | `#F7F8F8` | `SuperValue` titres, valeurs clés et libellés actifs |
| **Muted / Secondary Text** | `#8A8F98` | `SuperValue` métadonnées, identifiants d'issues, horodatages |
| **Hairline / Border** | `#23252A` | `borderColor` (`borderWidth: 1`) et `SuperSeparator.lineColor` |
| **Brand Accent + On-Accent** | `#5E6AD2` / `#FFFFFF` | Racine `"accent"`, `SuperAction` primaire (`backgroundColor` / `color`) |
| **Selected Row State** | `#1C1F2E` | `styles["<listId>:item"].states.selected.style.color` (bordure `#5E6AD2`) |
| **Semantic Success** | `#27A644` | `SuperIndicator` livré / résolu (fond badge `#112618`, texte `#4CC366`) |
| **Semantic Warning** | `#F2994A` | `SuperIndicator` en attente / priorité haute (fond `#2B1E12`, texte `#F5B06B`) |
| **Semantic Error** | `#E5484D` | `SuperIndicator` bloquant / critique (fond `#2C1315`, texte `#FF6B70`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Inter"`** pour l'ensemble de l'interface, les titres resserrés et les contrôles ; **`"JetBrains Mono"`** (ou `"Cascadia Mono"`) pour les clés de tickets (`ENG-142`), branches Git et compteurs alignés.
- **Rigueur d'alignement** : chiffres, estimations et dates alignés à droite (`textAlign: "end"`) dans les listes ; titres et statuts alignés à gauche (`"start"`).

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | `letterSpacing` | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `"Inter"` | `22` | `"semibold"` | `#F7F8F8` | `-0.4` | Titre de vue sprint ou compteur vélocité |
| **2. Section / Card Title** | `"Inter"` | `15` | `"semibold"` | `#F7F8F8` | `-0.2` | En-tête de panneau latéral, groupe de backlog |
| **3. Body / Field Value** | `"Inter"` | `13` | `"normal"` / `"medium"` | `#F7F8F8` | `0.0` | Titre de ticket en ligne (`medium`), champs `input` |
| **4. Issue Key / Git / Meta** | `"JetBrains Mono"` / `"Inter"` | `11` | `"normal"` | `#8A8F98` | `0.2` | Clé `ENG-142`, branche Git (`JetBrains Mono`), cycle, auteur |

## 4. Component Stylings
- **Cards & Panels (`Card`)** : `designSystem: "material"`, `color: "#111215"`, `radius: 8`, `borderWidth: 1`, `borderColor: "#23252A"`, `elevation: 0`, `padding: 16`.
- **Boutons (`SuperAction`)** :
  - *Primaire* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Inter"`, `backgroundColor: "#5E6AD2"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 6`, `fontSize: 13`, `fontWeight: "medium"`, `horizontalPadding: 12`, `verticalPadding: 8` (contraste AA garanti).
  - *Secondaire* : `variant: "outlined"`, `backgroundColor: "#181A1F"`, `borderColor: "#2E3138"`, `borderWidth: 1`, `color: "#F7F8F8"`, `iconColor: "#8A8F98"`, `radius: 6`.
  - *Tertiaire / Icône* : `variant: "text"` ou `variant: "icon"`, `color: "#8A8F98"`, `iconColor: "#8A8F98"`, `tooltip` obligatoire sur chaque action icône.
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : police `13px`, `color: "#F7F8F8"`, `field.fillColor: "#0C0D0F"`, `field.borderColor: "#23252A"`, `field.radius: 6`, `dense: true`.
- **Lignes de collection (`<listId>:item` & `Table`)** : fond repos `"#00000000"`, `radius: 6`, `paddingInsets: [6, 10, 6, 10]`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#16181D"`. État `states.selected` avec fond `#1C1F2E` et bordure `1px` `#5E6AD2`.
- **Pills de statut (`SuperIndicator`)** : `iconSize: 14`, `fontSize: 11`, `fontWeight: "medium"`, `radius: 999`, `borderWidth: 1`, `horizontalPadding: 8`, `verticalPadding: 3` (ex. en cours : `backgroundColor: "#1B1E36"`, `borderColor: "#3A428A"`, `color: "#9BA4F5"`, `iconColor: "#9BA4F5"`).

## 5. Layout Principles
- **Échelle d'espacement stricte** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding` reste à `0` ; les marges structurelles (`12` ou `16`) sont portées par `zoneFlows.<zone>.padding`.
- **Rayons concentriques** : Panneau parent `radius: 8` $\rightarrow$ Sous-groupe `radius: 6` $\rightarrow$ Ligne / Bouton / Badge `radius: 6` (ou `999` pour un pill compact).
- **Calibrage haute densité Desktop** : `ListView` avec `itemExtent: 38` (liste d'issues compacte 1 ligne) ou `48` (avec sous-titre), `spacing: 2` ou `4`. `SuperTable` avec `headerRowHeight: 34` et `rowHeight: 36`.

## 6. Depth & Elevation
- **Système de surface** : `designSystem: "material"` sur l'intégralité de l'écran, strictement plat (`elevation: 0`).
- **Stratégie de séparation** : zéro ombre portée sur les cartes au repos ; la hiérarchie repose sur les paliers de luminance (`#08090A` $\rightarrow$ `#111215` $\rightarrow$ `#181A1F`) et des filets `1px` `#23252A`.
- **Surfaces flottantes uniquement** : si une carte inspecteur ou modale isolée nécessite du détachement, utiliser une ombre sèche discrète (`shadow: { "enabled": true, "color": "#000000", "opacity": 0.45, "blur": 20, "spread": -4, "dx": 0, "dy": 8 }`) sans halo néon.

## 7. Do's and Don'ts
- **Do** : Réserver `#5E6AD2` au seul bouton d'action primaire de la vue et au filet de sélection active.
- **Do** : Afficher les identifiants courts (`ENG-204`) et noms de branches Git en `"JetBrains Mono"` (ou `"Cascadia Mono"`) `11px` `#8A8F98` à gauche du titre de ligne.
- **Do** : Maintenir `padding >= spacing` dans chaque `Card` (ex. `padding: 16`, `spacing: 8` ou `12`).
- **Do** : Révéler les actions rapides de ligne (`edit`, `more_horiz`) en zone `east` via `states.automatic.contentHover`.
- **Don't** : Ne jamais utiliser d'ombres portées épaisses (`elevation > 1`) ni de grands rayons mous (`radius > 10`).
- **Don't** : Ne jamais saturer l'arrière-plan de dégradés violets ou de halos `neon`.
- **Don't** : Ne jamais étirer un bouton `"filled"` sur toute la largeur d'un panneau Desktop (`fitContent: true`).
- **Don't** : Ne jamais empiler plus de 3 tailles de police dans une même carte KPI ou fiche d'issue.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (`mainLayout`)** : volet `west` fixe (`westSize: 280` à `320`, `resizeSides: true`, `"autoSides": []`) listant les tickets ou vues filtrées ; zone `center` (`expandSlots: true`) affichant la fiche détaillée liée via `[?]`.
- **Bandeau KPI / Cycle** : zone `north` compacte (`northSize: 88` à `96`, `zoneAxes.north: "row"`, `spacing: 12`) alignant 3 ou 4 métriques concises.
- **Formulaires d'édition** : borner la largeur de lecture à `680px`–`740px` (`slotSizeConstraints`) et définir `"autoSides": []` sur tout layout ayant `scrollable: true`.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "dark",
  "accent": "#5E6AD2",
  "components": {
    "title-cycle": {
      "type": "value",
      "text": "Cycle actif · Sprint 14",
      "fontFamily": "Inter",
      "fontSize": 22,
      "fontWeight": "semibold",
      "letterSpacing": -0.4,
      "color": "#F7F8F8"
    },
    "row-issue-key": {
      "type": "value",
      "binding": "issues[?].key",
      "fontFamily": "JetBrains Mono",
      "fontSize": 11,
      "color": "#8A8F98"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#08090A",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#111215",
      "radius": 8,
      "borderWidth": 1,
      "borderColor": "#23252A",
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
      "hoverColor": "#16181D",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#1C1F2E",
            "borderWidth": 1,
            "borderColor": "#5E6AD2"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
