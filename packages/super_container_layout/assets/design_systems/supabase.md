---
name: "Supabase"
slug: "supabase"
category: "developer-tools"
tagline: "Console backend carbone #121212, cartes #1C1C1C bordées et émeraude signature #3ECF8E"
description: "Système visuel sombre orienté développeurs associant des surfaces neutres gris carbone #121212 et #1C1C1C, des bordures nettes #2E2E2E et une accentuation émeraude électrique #3ECF8E. Idéal pour les consoles Postgres/SQL, panneaux d'authentification, explorateurs de stockage, gestionnaires d'API et back-offices techniques."
mode: "dark"
accent: "#3ECF8E"
canvasColor: "#121212"
surfaceColor: "#1C1C1C"
textColor: "#EDEDED"
mutedTextColor: "#8F8F8F"
borderColor: "#2E2E2E"
cardRadius: 8
surfaceSystem: "material"
fontFamily: "Inter"
---

# Supabase — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette esthétique incarne une **console d'ingénierie backend moderne, pragmatique et limpide**. Bâtie sur des gris neutres achromatiques (`#121212` pour le canevas, `#1C1C1C` pour les conteneurs et `#2E2E2E` pour les filets), elle évite toute coloration bleutée parasite afin de faire ressortir avec éclat le **vert émeraude signature `#3ECF8E`**. L'atmosphère combine la rigueur d'un studio SQL/API et le confort visuel d'un tableau de bord SaaS structuré.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les consoles backend open-source modernes, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#121212` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#1C1C1C` | `styles["<cardId>"].color` (cartes de tables, politiques RLS, KPI) |
| **Elevated / Secondary Surface** | `#242424` | Barres d'outils SQL, en-têtes de grilles, `tabBarStyle`, encarts code |
| **Primary Text** | `#EDEDED` | `SuperValue` noms de tables, compteurs de requêtes, valeurs métier |
| **Muted / Secondary Text** | `#8F8F8F` | `SuperValue` types Postgres (`uuid`, `timestamptz`), descriptions |
| **Hairline / Border** | `#2E2E2E` | `borderColor` (`borderWidth: 1`) et `SuperSeparator.lineColor` |
| **Brand Accent + On-Accent** | `#3ECF8E` / `#092216` | Racine `"accent"`, `SuperAction` primaire `"filled"` (texte sombre obligatoire !) |
| **Selected Row State** | `#162B22` | `styles["<listId>:item"].states.selected.style.color` (bordure `#3ECF8E`) |
| **Semantic Success** | `#3ECF8E` | `SuperIndicator` Healthy / RLS Enabled (fond `#122B20`, texte `#3ECF8E`) |
| **Semantic Warning** | `#F59E0B` | `SuperIndicator` Degraded / Unindexed (fond `#2B200D`, texte `#FBBF24`) |
| **Semantic Error** | `#EF4444` | `SuperIndicator` Offline / Auth Denied (fond `#2D1414`, texte `#F87171`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Inter"`** pour la navigation de console, les titres et les libellés ; **`"JetBrains Mono"`** (ou **`"Cascadia Mono"`**) systématique pour les noms de colonnes SQL (`user_id`), UUIDs, clés publiques, endpoints REST (`/rest/v1/users`) et temps d'exécution (`4.2 ms`).
- **Lisibilité technique** : séparer strictement le nom d'une colonne et son type de donnée ou sa valeur dans des `SuperValue` distincts.

| Niveau (`SuperValue`) | `fontSize` | `fontWeight` | `color` | Famille conseillée | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `22`–`24` | `"semibold"` | `#EDEDED` | `"Inter"` | Titre de base (`Database`) ou volume requêtes/s |
| **2. Section / Card Title** | `16` | `"semibold"` | `#EDEDED` | `"Inter"` | Titre de panneau (`Row Level Security`, `Buckets`) |
| **3. Body / Record Cell** | `13` | `"normal"` | `#EDEDED` | `"Inter"` / `"JetBrains Mono"` | Valeur d'enregistrement, colonne `user_id`, UUID |
| **4. Label / Schema Type** | `11`–`12` | `"normal"` | `#8F8F8F` | `"JetBrains Mono"` | Type SQL `int8`, endpoint REST, région `eu-west-1` |

## 4. Component Stylings
- **Cards & Console Panels (`Card`)** : `designSystem: "material"`, `color: "#1C1C1C"`, `radius: 8`, `borderWidth: 1`, `borderColor: "#2E2E2E"`, `elevation: 0`, `padding: 16` ou `20`.
- **Boutons (`SuperAction`)** :
  - *Primaire émeraude (règle AA critique)* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Inter"`, `backgroundColor: "#3ECF8E"`, **`color: "#092216"`**, **`iconColor: "#092216"`** (ou `"#121212"` — ne jamais mettre de texte blanc `#FFFFFF` sur `#3ECF8E`, le contraste serait insuffisant ; `#092216` atteint un ratio > 9:1 AAA), `radius: 6`, `fontSize: 13`, `fontWeight: "semibold"`, `horizontalPadding: 14`, `verticalPadding: 8`.
  - *Secondaire* : `variant: "outlined"`, `fontFamily: "Inter"`, `backgroundColor: "#242424"`, `borderColor: "#383838"`, `borderWidth: 1`, `color: "#EDEDED"`, `iconColor: "#8F8F8F"`, `radius: 6`.
  - *Action destructrice (`Drop` / `Revoke`)* : `variant: "outlined"`, `fontFamily: "Inter"`, `backgroundColor: "#291415"`, `borderColor: "#7F1D1D"`, `color: "#F87171"`, `iconColor: "#F87171"`.
- **Champs & Paramètres (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"` (ou `"JetBrains Mono"` pour les endpoints REST et filtres SQL), `field.fillColor: "#161616"`, `field.borderColor: "#2E2E2E"`, `field.radius: 6`, `color: "#EDEDED"`. Privilégier `switch` pour activer `RLS`, `Realtime` ou `Webhooks`.
- **Tables SQL & Listes (`SuperTable` & `<listId>:item`)** :
  - `SuperTable` : `headerRowHeight: 36`, `rowHeight: 36`, police `"JetBrains Mono"` (ou `"Cascadia Mono"`) sur les colonnes SQL (`user_id`), UUIDs et horodatages ISO.
  - `<listId>:item` : `color: "#00000000"`, `radius: 6`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#242424"`, et `states.selected` en `#162B22` avec bordure `1px` `#3ECF8E`.
- **Badges de schéma & statut (`SuperIndicator`)** : `radius: 999` en `"Inter"` pour les états de santé (`Healthy`, `Active`) et `radius: 4` en `"JetBrains Mono"` (`backgroundColor: "#242424"`, `borderColor: "#383838"`, `color: "#A3A3A3"`) pour les badges `PK`, `FK`, `GET`, `POST`.

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding: 0` ; `zoneFlows.*.padding: 16`, `spacing: 12`.
- **Rayons concentriques sobres** : Carte `radius: 8` $\rightarrow$ Bouton / Champ / Ligne `radius: 6` $\rightarrow$ Badge technique HTTP/SQL `radius: 4`.
- **Calibrage Desktop** : `ListView` de schémas/tables avec `itemExtent: 40`–`46`, `spacing: 4` ; `SuperTable` d'enregistrements avec `headerRowHeight: 36` et `rowHeight: 36`.

## 6. Depth & Elevation
- **Construction plate par luminance achromatique** : `designSystem: "material"` et `elevation: 0`. La progression `#121212` (fond) $\rightarrow$ `#1C1C1C` (carte) $\rightarrow$ `#242424` (sous-bloc) encadrée par `#2E2E2E` offre une lisibilité nette sans ombres portées.
- **Accentuation sobre** : aucun halo `neon` permanent ; réserver la teinte `#162B22` / `#3ECF8E` aux sélections actives et indicateurs opérationnels.

## 7. Do's and Don'ts
- **Do** : Toujours associer `backgroundColor: "#3ECF8E"` à `color: "#092216"` (ou `"#121212"`) et `iconColor: "#092216"` sur les boutons `"filled"`.
- **Do** : Utiliser `"JetBrains Mono"` / `"Cascadia Mono"` pour tous les noms de colonnes SQL, UUIDs, endpoints REST et métriques serveur.
- **Do** : Isoler les actions dangereuses (`Supprimer le bucket`, `Révoquer la clé`) dans une carte dédiée en bas de formulaire avec bouton rouge bordé.
- **Do** : Structurer les explorateurs de tables en Maître (`west` liste des tables) / Détail (`center` `SuperTable` ou structure des colonnes).
- **Don't** : Ne jamais écrire en blanc `#FFFFFF` sur un fond plein `#3ECF8E`.
- **Don't** : Ne jamais colorer tout un panneau en vert émeraude : 90 % de l'écran doit rester gris carbone neutre.
- **Don't** : Ne jamais dépasser `radius: 8` sur les conteneurs principaux.
- **Don't** : Ne jamais mettre `"autoSides"` sur un layout contenant une zone `scrollable: true`.

## 8. Responsive & Desktop Ergonomics
- **Explorateur de Schéma + Grille (`mainLayout`)** : volet `west` (`westSize: 270`–`300`, `resizeSides: true`, `"autoSides": []`) listant tables, buckets ou fonctions Edge ; zone `center` (`expandSlots: true`) présentant les onglets `SuperTab` (`Données`, `Colonnes`, `Politiques RLS`, `Logs`).
- **Formulaires de configuration projet** : cartes `#1C1C1C` empilées dans une vue défilante (`scrollable: true`, `"autoSides": []`, `maxWidth: "780px"`).

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "dark",
  "accent": "#3ECF8E",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#121212",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#1C1C1C",
      "radius": 8,
      "borderWidth": 1,
      "borderColor": "#2E2E2E",
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
      "hoverColor": "#242424",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#162B22",
            "borderWidth": 1,
            "borderColor": "#3ECF8E"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "panel-title": {
      "type": "value",
      "text": "Row Level Security",
      "fontFamily": "Inter",
      "fontSize": 16,
      "fontWeight": "semibold",
      "color": "#EDEDED"
    },
    "col-uuid": {
      "type": "value",
      "label": "user_id",
      "text": "550e8400-e29b-41d4-a716-446655440000",
      "fontFamily": "JetBrains Mono",
      "fontSize": 12,
      "color": "#EDEDED"
    }
  }
}
```
