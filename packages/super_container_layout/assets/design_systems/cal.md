---
name: "Cal.com"
slug: "cal"
category: "productivity-saas"
tagline: "Studio SaaS monochrome ultra-net, cartes blanches franches et contraste encre noire"
description: "Système de design clair architectural reposant sur un canevas gris froid #F3F4F6, des cartes #FFFFFF nettement cernées de #E5E7EB et des actions primaires noir d'encre #111827 à contraste maximal. Idéal pour la planification, les portails clients, la réservation de ressources, la facturation et les paramètres SaaS."
mode: "light"
accent: "#111827"
canvasColor: "#F3F4F6"
surfaceColor: "#FFFFFF"
textColor: "#111827"
mutedTextColor: "#6B7280"
borderColor: "#E5E7EB"
cardRadius: 10
surfaceSystem: "material"
fontFamily: "Inter"
---

# Cal.com — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette direction visuelle cultive une **rigueur studio monochrome suisse** : franche, utilitaire, confiante et immédiatement lisible. Le contraste net entre le fond d'atelier gris froid (`#F3F4F6`) et les cartes blanc pur (`#FFFFFF`) bordées d'un trait précis (`#E5E7EB`) organise l'espace en modules impeccables. Plutôt qu'un bleu ou un violet décoratif, l'accentuation repose sur un **anthracite profond `#111827`** qui confère une autorité éditoriale aux actions principales et aux créneaux sélectionnés.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les interfaces SaaS monochromes contemporaines, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#F3F4F6` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#FFFFFF` | `styles["<cardId>"].color` (cartes d'événements, grilles horaires, formulaires) |
| **Elevated / Secondary Surface** | `#F9FAFB` | Sous-blocs de disponibilité, entêtes de tableau, `tabBarStyle` |
| **Primary Text** | `#111827` | `SuperValue` titres, créneaux horaires, libellés principaux |
| **Muted / Secondary Text** | `#6B7280` | `SuperValue` fuseaux horaires, durées secondaires, descriptions |
| **Hairline / Border** | `#E5E7EB` | `borderColor` (`borderWidth: 1`) et `SuperSeparator.lineColor` |
| **Brand Accent + On-Accent** | `#111827` / `#FFFFFF` | Racine `"accent"`, `SuperAction` primaire `"filled"` (contraste AAA > 15:1) |
| **Selected Row State** | `#F3F4F6` | `styles["<listId>:item"].states.selected.style.color` (bordure `#111827`) |
| **Semantic Success** | `#15803D` | `SuperIndicator` confirmé / actif (fond `#DCFCE7`, texte `#166534`) |
| **Semantic Warning** | `#B45309` | `SuperIndicator` en attente de validation (fond `#FEF3C7`, texte `#92400E`) |
| **Semantic Error** | `#B91C1C` | `SuperIndicator` annulé / conflit horaire (fond `#FEE2E2`, texte `#991B1B`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Inter"`** avec des graisses `"semibold"` et `"bold"` affirmées pour les titres display et l'interface générale (repli `"Segoe UI"`) ; **`"Cascadia Mono"`** pour les durées (`30m`, `45m`), slugs de réservation (`/equipe/point-30min`) et codes de référence.
- **Clarté numérique** : aligner systématiquement les heures, durées et tarifs à droite (`textAlign: "end"`).

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | `letterSpacing` | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `"Inter"` | `22`–`24` | `"bold"` | `#111827` | `-0.4` | Titre display (`Types d'événements`), KPI rendez-vous |
| **2. Section / Card Title** | `"Inter"` | `16` | `"semibold"` | `#111827` | `-0.2` | Titre de carte de configuration ou disponibilité |
| **3. Body / Field Value** | `"Inter"` | `14` | `"normal"` / `"medium"` | `#111827` | `0.0` | Intitulé de rendez-vous (`medium`), saisie formulaire |
| **4. Slug / Durée / Metadata** | `"Cascadia Mono"` / `"Inter"` | `12` | `"normal"` | `#6B7280` | `0.1` | Durée `30m`, slug URL (`Cascadia Mono`), fuseau `Europe/Paris` |

## 4. Component Stylings
- **Cards & Panels (`Card`)** : `designSystem: "material"`, `color: "#FFFFFF"`, `radius: 10`, `borderWidth: 1`, `borderColor: "#E5E7EB"`, `elevation: 0`, `padding: 16` ou `20`.
- **Boutons (`SuperAction`)** :
  - *Primaire* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Inter"`, `backgroundColor: "#111827"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 8`, `fontSize: 13`, `fontWeight: "semibold"`, `horizontalPadding: 14`, `verticalPadding: 9`.
  - *Secondaire* : `variant: "outlined"`, `fontFamily: "Inter"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#D1D5DB"`, `borderWidth: 1`, `color: "#111827"`, `iconColor: "#374151"`, `radius: 8`.
  - *Tertiaire / Icône* : `variant: "text"` ou `variant: "icon"`, `color: "#4B5563"`, `iconColor: "#6B7280"`, `radius: 8`, avec `tooltip` explicite (`"Copier le lien"`, `"Paramètres"`).
- **Contrôles & Champs (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"`, `field.fillColor: "#FFFFFF"`, `field.borderColor: "#D1D5DB"`, `field.radius: 8`, `color: "#111827"`. Utiliser `kind: "boolean"` avec `switch` pour activer/désactiver une plage de disponibilité, et `choice` (`variant: "segmented"`) pour basculer entre `À venir / Passés / Annulés`.
- **Collections (`<listId>:item` & `Table`)** : lignes sur carte blanche avec `color: "#FFFFFF"`, `radius: 8`, `borderWidth: 1`, `borderColor: "#E5E7EB"` (pour des cartes-lignes d'événements espacées de `spacing: 8`) ou `"#00000000"` dans une liste continue, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#F9FAFB"`. `states.selected` applique `color: "#F3F4F6"`, `borderWidth: 1`, `borderColor: "#111827"`.
- **Badges de durée & statut (`SuperIndicator`)** : badges neutres techniques (`fontFamily: "Cascadia Mono"`, `backgroundColor: "#F3F4F6"`, `borderColor: "#E5E7EB"`, `borderWidth: 1`, `color: "#374151"`, `iconColor: "#6B7280"`, `radius: 6`, `fontSize: 11`, `fontWeight: "medium"`) et pills sémantiques réservés aux statuts réels.

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding: 0` ; gouttières entre cartes `zoneFlows.*.spacing: 12` ou `16` pour laisser apparaître le canevas `#F3F4F6`.
- **Rayons concentriques** : `Card` principale `radius: 10` $\rightarrow$ Sous-conteneur / Bouton / Champ / Ligne `radius: 8` $\rightarrow$ Badge compact `radius: 6`.
- **Calibrage Desktop** : `ListView` riche (titre + durée + participants) avec `itemExtent: 56`–`64`, `spacing: 6`. `SuperTable` avec `headerRowHeight: 38` et `rowHeight: 40`.

## 6. Depth & Elevation
- **Clarté architecturale sans flou** : `designSystem: "material"`, `elevation: 0` par défaut. La séparation figure/fond entre `#FFFFFF` et `#F3F4F6` couplée au filet `#E5E7EB` produit une profondeur nette sans recourir aux ombres lourdes.
- **Micro-ombre optionnelle** : sur les cartes KPI autonomes uniquement, une ombre subtile (`shadow: { "enabled": true, "color": "#111827", "opacity": 0.04, "blur": 8, "spread": 0, "dx": 0, "dy": 2 }`) peut renforcer l'assise tactile.

## 7. Do's and Don'ts
- **Do** : Conserver une palette strictement monochrome (`#111827`, `#6B7280`, `#E5E7EB`, `#F3F4F6`, `#FFFFFF`) à 95 %, en limitant la couleur vive aux seuls badges de statut.
- **Do** : Déclarer explicitement `color: "#FFFFFF"` et `iconColor: "#FFFFFF"` sur le bouton primaire `#111827`.
- **Do** : Utiliser des contrôles `segmented` nets pour filtrer les vues temporelles (`Jour`, `Semaine`, `Mois`).
- **Do** : Aligner les actions secondaires (`"Copier"`, `"Aperçu"`) dans une barre horizontale compacte (`spacing: 8`).
- **Don't** : Ne jamais introduire de dégradés colorés sur les arrière-plans ou les boutons.
- **Don't** : Ne jamais poser du texte gris clair sur fond `#F3F4F6` sans vérifier le contraste (`#6B7280` minimum).
- **Don't** : Ne jamais mélanger `liquidGlass` ou `neumorphism` avec cette rigueur éditoriale.
- **Don't** : Ne jamais laisser un formulaire de configuration s'étirer sur `1400px` sans contrainte `maxWidth`.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail opérationnel** : `westSize: 310` à `340` (`resizeSides: true`, `"autoSides": []`) pour le catalogue de créneaux ou de réservations ; panneau `center` `#FFFFFF` (`expandSlots: true`) pour l'éditeur de règles et disponibilités lié via `[?]`.
- **Panneaux de paramètres SaaS** : structure verticale défilante (`scrollable: true`, `"autoSides": []`, `spacing: 16`, `padding: 20`) centrée avec `maxWidth: "760px"`, regroupant chaque domaine fonctionnel dans sa propre `Card` `#FFFFFF`.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "light",
  "accent": "#111827",
  "components": {
    "title-main": {
      "type": "value",
      "text": "Types d'événements",
      "fontFamily": "Inter",
      "fontSize": 24,
      "fontWeight": "bold",
      "letterSpacing": -0.4,
      "color": "#111827"
    },
    "badge-duration": {
      "type": "indicator",
      "icon": "schedule",
      "label": "30m",
      "fontFamily": "Cascadia Mono",
      "fontSize": 11,
      "fontWeight": "medium",
      "backgroundColor": "#F3F4F6",
      "borderColor": "#E5E7EB",
      "borderWidth": 1,
      "color": "#374151",
      "iconColor": "#6B7280",
      "radius": 6
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#F3F4F6",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 10,
      "borderWidth": 1,
      "borderColor": "#E5E7EB",
      "elevation": 0,
      "padding": 20
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 8,
      "borderWidth": 1,
      "borderColor": "#E5E7EB",
      "paddingInsets": [8, 12, 8, 12],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#F9FAFB",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#F3F4F6",
            "borderWidth": 1,
            "borderColor": "#111827"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
