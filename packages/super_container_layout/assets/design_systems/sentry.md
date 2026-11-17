---
name: "Sentry"
slug: "sentry"
category: "developer-tools"
tagline: "Observabilité obsidienne-prune #181225, cartes télémétriques #221A33 et alertes haute priorité"
description: "Système visuel sombre expressif ancré dans un canevas prune-obsidienne #181225 et des cartes #221A33 bordées de #362B4D, dynamisé par un violet #6C5FC7 et des signaux d'incident corail #E5534B et ambre #F5B041. Conçu pour le monitoring d'erreurs, l'APM, le triage d'alertes SRE et l'analyse de traces."
mode: "dark"
accent: "#6C5FC7"
canvasColor: "#181225"
surfaceColor: "#221A33"
textColor: "#F5F3F7"
mutedTextColor: "#A69EB8"
borderColor: "#362B4D"
cardRadius: 10
surfaceSystem: "material"
fontFamily: "Rubik"
---

# Sentry — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette direction visuelle marie une **identité nocturne prune-obsidienne singulière** à une **ergonomie de salle de contrôle SRE haute vigilance**. Contrairement aux consoles grises génériques, l'ensemble des neutres est infusé d'une sous-teinte aubergine profonde (`#181225` pour le fond, `#221A33` pour les cartes, `#362B4D` pour les bordures et `#A69EB8` pour les textes secondaires), créant une harmonie chromatique riche sur laquelle les courbes de télémétrie, le violet d'action `#6C5FC7` et les marqueurs d'incidents (`#E5534B`, `#F5B041`) se détachent avec une clarté immédiate.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les plateformes modernes d'observabilité et de suivi d'exceptions, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#181225` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#221A33` | `styles["<cardId>"].color` (cartes KPI crash-free, graphiques APM, stacktraces) |
| **Elevated / Secondary Surface** | `#2C2242` | Barres de requêtes/filtres, en-têtes de traces, `tabBarStyle` |
| **Primary Text** | `#F5F3F7` | `SuperValue` classes d'exceptions, compteurs d'événements, titres |
| **Muted / Secondary Text** | `#A69EB8` | `SuperValue` releases (`v2.14.0`), environnements, durées `p95` |
| **Hairline / Border** | `#362B4D` | `borderColor` (`borderWidth: 1`) et traits `SuperSeparator` |
| **Brand Accent + On-Accent** | `#6C5FC7` / `#FFFFFF` | Racine `"accent"`, `SuperAction` primaire `"filled"` (contraste AA > 5.2:1) |
| **Selected Row State** | `#31254D` | `styles["<listId>:item"].states.selected.style.color` (bordure `#6C5FC7`) |
| **Semantic Success (Healthy)** | `#2ECC71` | `SuperIndicator` Crash-Free / Resolved (fond `#142E26`, texte `#58D68D`) |
| **Semantic Warning (Regression)** | `#F5B041` | `SuperIndicator` Degraded / Warning (fond `#332518`, texte `#F5B041`) |
| **Semantic Error (Fatal)** | `#E5534B` | `SuperIndicator` Unhandled / P1 Incident (fond `#381924`, texte `#FF7B73`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Rubik"`** pour les titres, grands KPIs et l'interface analytique ; **`"JetBrains Mono"`** (ou **`"Cascadia Mono"`**) indispensable pour les types d'exceptions (`StateError`, `TimeoutException`), frames de stacktrace, requêtes de filtrage `is:unresolved` et latences `p50`/`p95`/`p99`.
- **Hiérarchie de triage** : mettre en avant le type d'exception (`semibold` `#F5F3F7` en `"JetBrains Mono"`) séparément de la route fautive et du volume d'occurrences aligné à droite (`"end"`).

| Niveau (`SuperValue`) | `fontSize` | `fontWeight` | `color` | Famille conseillée | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `24` | `"bold"` | `#F5F3F7` | `"Rubik"` | Taux `99.94% Crash-Free`, volume d'erreurs 24h |
| **2. Section / Card Title** | `16` | `"semibold"` | `#F5F3F7` | `"Rubik"` | Titre de graphique (`Aperçu APM`), détail d'incident |
| **3. Issue Title / Query** | `13`–`14` | `"medium"` | `#F5F3F7` | `"JetBrains Mono"` / `"Rubik"` | Signature d'exception, requête `is:unresolved`, filtre |
| **4. Telemetry Metadata** | `11`–`12` | `"normal"` | `#A69EB8` | `"JetBrains Mono"` | Latence `p95`, stacktrace frame, release `web@4.8.1` |

## 4. Component Stylings
- **Telemetry Cards (`Card`)** : `designSystem: "material"`, `color: "#221A33"`, `radius: 10`, `borderWidth: 1`, `borderColor: "#362B4D"`, `elevation: 0`, `padding: 16`. Pour une carte d'alerte critique P1, utiliser une bordure latérale gauche accentuée (`borderWidths: [1, 1, 1, 4]`, `borderColor: "#E5534B"`).
- **Boutons (`SuperAction`)** :
  - *Primaire (Résoudre / Créer une alerte)* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Rubik"`, `backgroundColor: "#6C5FC7"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 8`, `fontSize: 13`, `fontWeight: "semibold"`, `horizontalPadding: 14`, `verticalPadding: 8`.
  - *Secondaire (Assigner / Archiver / Ignorer)* : `variant: "outlined"`, `fontFamily: "Rubik"`, `backgroundColor: "#2C2242"`, `borderColor: "#463863"`, `borderWidth: 1`, `color: "#F5F3F7"`, `iconColor: "#A69EB8"`, `radius: 8`.
  - *Icône de barre d'action* : `variant: "icon"`, `iconColor: "#A69EB8"`, `tooltip` explicite.
- **Barre de filtre télémétrique (`SuperValue` en `mode: "input"`)** : `field.fillColor: "#1B142B"`, `field.borderColor: "#362B4D"`, `field.radius: 8`, `color: "#F5F3F7"`, `fontFamily: "JetBrains Mono"` (ou `"Cascadia Mono"`) pour les requêtes `is:unresolved level:error`. Sélecteurs de fenêtre (`1h`, `24h`, `7d`, `14d`) en `choice` `variant: "segmented"` (`fontFamily: "Rubik"`).
- **Flux d'incidents & Traces (`<listId>:item` & `Table`)** :
  - `<listId>:item` : `color: "#00000000"`, `radius: 8`, `paddingInsets: [8, 12, 8, 12]`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#2A2040"`. `states.selected` applique `#31254D` et une bordure `1px` `#6C5FC7`.
- **Badges de sévérité (`SuperIndicator`)** : `fontFamily: "JetBrains Mono"`, `radius: 6`, `fontSize: 11`, `fontWeight: "semibold"`, `iconSize: 13`, `borderWidth: 1`, `horizontalPadding: 8`, `verticalPadding: 3`, liés au niveau de sévérité (`fatal` $\rightarrow$ `#E5534B`, `warning` $\rightarrow$ `#F5B041`, `resolved` $\rightarrow$ `#2ECC71`) via `states.binding` + `states.named`.

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding: 0` ; `zoneFlows.*.padding: 16`, `spacing: 12`.
- **Rayons concentriques** : `Card` télémétrique `radius: 10` $\rightarrow$ Ligne / Champ / Bouton `radius: 8` $\rightarrow$ Badge de sévérité `radius: 6`.
- **Calibrage Desktop** : `ListView` de triage d'erreurs avec `itemExtent: 56`–`62` (signature d'erreur + route + compteurs événements/utilisateurs), `spacing: 4` ; `SuperTable` de transactions APM avec `headerRowHeight: 36` et `rowHeight: 38`.

## 6. Depth & Elevation
- **Stratification prune-obsidienne** : `designSystem: "material"`, `elevation: 0` sur les grilles et listes, complétée sur les cartes KPI majeures par une ombre subtile teintée (`shadow: { "enabled": true, "color": "#0A0612", "opacity": 0.35, "blur": 16, "spread": -2, "dx": 0, "dy": 6 }`).
- **Graphiques (`SuperChart`)** : harmoniser les séries avec `#6C5FC7` (trafic/p50), `#F5B041` (p95) et `#E5534B` (erreurs) sur fond `#221A33`.

## 7. Do's and Don'ts
- **Do** : Teinter systématiquement toutes les surfaces et bordures dans la gamme prune (`#181225`, `#221A33`, `#2C2242`, `#362B4D`) plutôt qu'en gris neutre froid.
- **Do** : Réserver le rouge `#E5534B` et l'ambre `#F5B041` aux véritables incidents, régressions et seuils dépassés.
- **Do** : Présenter les compteurs `Events` et `Users` alignés à droite en police chasse fixe à côté des badges de sévérité.
- **Do** : Verrouiller `color: "#FFFFFF"` et `iconColor: "#FFFFFF"` sur le bouton primaire `#6C5FC7`.
- **Don't** : Ne jamais saturer le fond avec un violet vif illisible : la base `#181225` doit rester très sombre.
- **Don't** : Ne jamais mélanger des cartes grises `#1C1C1C` non teintées au milieu des panneaux `#221A33`.
- **Don't** : Ne jamais remplacer une pile de frames ou d'attributs de contexte par un bloc `textarea` brut.
- **Don't** : Ne jamais omettre `"autoSides": []` sur un volet de triage défilant.

## 8. Responsive & Desktop Ergonomics
- **Dashboard Observabilité + Triage (`mainLayout`)** : zone `north` avec barre de filtre d'environnement/période et 4 cartes KPI (`Crash-Free Sessions`, `Erreurs non résolues`, `Apdex`, `Latence p95` — `northSize: 112`, `zoneAxes.north: "row"`, `spacing: 12`) ; zone `west` (`westSize: 360`, `resizeSides: true`, `"autoSides": []`) listant le flux d'incidents ; zone `center` (`expandSlots: true`) affichant le graphique `SuperChart`, les tags d'environnement et les détails de l'incident sélectionné via `[?]`.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "dark",
  "accent": "#6C5FC7",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#181225",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#221A33",
      "radius": 10,
      "borderWidth": 1,
      "borderColor": "#362B4D",
      "elevation": 0,
      "padding": 16
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 8,
      "paddingInsets": [8, 12, 8, 12],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#2A2040",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#31254D",
            "borderWidth": 1,
            "borderColor": "#6C5FC7"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "kpi-crash-free": {
      "type": "value",
      "label": "Sessions stables",
      "text": "99.94%",
      "fontFamily": "Rubik",
      "fontSize": 24,
      "fontWeight": "bold",
      "color": "#F5F3F7"
    },
    "query-issues": {
      "type": "value",
      "mode": "input",
      "text": "is:unresolved level:error",
      "fontFamily": "JetBrains Mono",
      "fontSize": 13,
      "color": "#F5F3F7",
      "field": {
        "fillColor": "#1B142B",
        "borderColor": "#362B4D",
        "radius": 8
      }
    },
    "latency-p95": {
      "type": "indicator",
      "icon": "warning",
      "label": "p95 · 412ms",
      "fontFamily": "JetBrains Mono",
      "fontSize": 11,
      "fontWeight": "semibold",
      "color": "#F5B041",
      "iconColor": "#F5B041",
      "backgroundColor": "#332518",
      "borderColor": "#F5B041",
      "borderWidth": 1,
      "radius": 6,
      "horizontalPadding": 8,
      "verticalPadding": 3
    }
  }
}
```
