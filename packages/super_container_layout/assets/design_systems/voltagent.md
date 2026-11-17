---
name: "VoltAgent"
slug: "voltagent"
category: "ai-platforms"
tagline: "Console télémétrique noir absolu et signal émeraude haute précision pour orchestrateurs d'agents IA."
description: "Interface d'observabilité nocturne bâtie sur un fond vide sidéral (#050505), des panneaux techniques à angles vifs (#0F1110, rayon 6px) et un signal émeraude électrique (#10B981). Idéal pour l'orchestration multi-agents, les traces d'exécution LLM, les consoles DevOps et le monitoring temps réel."
mode: "dark"
accent: "#10B981"
canvasColor: "#050505"
surfaceColor: "#0F1110"
textColor: "#F3F4F6"
mutedTextColor: "#71717A"
borderColor: "#1F2924"
cardRadius: 6
surfaceSystem: "material"
fontFamily: "Geist Mono"
---

# VoltAgent — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
Conçue comme un poste de télémétrie pour systèmes d'agents autonomes, cette direction visuelle plonge l'interface dans un noir profond `#050505` où seules l'architecture des panneaux `#0F1110` et les impulsions émeraude `#10B981` captent le regard. Les rayons d'arrondi volontairement tendus (`6px`), les bordures légèrement teintées de vert carbone `#1F2924` et la prédominance de **`"Geist Mono"`** (épaulée par **`"Geist"`** pour les textes narratifs et descriptions de sections) évoquent la rigueur d'un analyseur logique moderne, privilégiant la densité d'information, la vitesse de balayage visuel et la lisibilité instantanée des états d'exécution.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas vide noir** | `#050505` | `styles["background"].color` — arrière-plan console (`padding: 0`) |
| **Panneau télémétrique** | `#0F1110` | `Card`, inspecteur de nœud, conteneur de graphe ou de traces |
| **Sous-surface élevée** | `#161A18` | En-têtes de tableaux, `tabBarStyle` et champs de saisie |
| **Bordure carbone-émeraude** | `#1F2924` | Filet `1px` précis délimitant chaque module sur le fond noir |
| **Texte primaire clair** | `#F3F4F6` | Valeurs clés, identifiants d'agents et libellés principaux |
| **Texte muet zinc** | `#71717A` | Horodatages ms, métadonnées secondaires, unités et clés d'attributs |
| **Signal Émeraude** | `#10B981` | Racine `"accent"`, CTA primaire, nœud actif et bordure sélectionnée |
| **Encre sur Émeraude** | `#050505` | Texte/icône sombre obligatoire sur bouton plein `#10B981` (contraste AA+) |
| **Surface sélectionnée** | `#0A261E` | Fond de trace/agent sélectionné (`states.selected`) |
| **Alerte / Échec d'outil** | `#EF4444` | Erreur d'appel d'outil ou timeout sur pastille `#2A1215` |

## 3. Typography Rules
Utilisez **`"Geist Mono"`** comme voix principale pour les métriques télémétriques, badges d'agents, journaux d'exécution, champs `input`, compteurs de tokens et durées en millisecondes, associée à **`"Geist"`** pour les titres de sections lisibles et les descriptions narratives.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. KPI télémétrique / Titre** | `"Geist Mono"` | `22` | `"bold"` | `"#F3F4F6"` | Latence P95, débit d'appels, coût total ou titre de console |
| **2. En-tête & Description** | `"Geist"` | `16` | `"semibold"` | `"#F3F4F6"` | Titre de `Card` et description narrative de workflow |
| **3. Ligne d'agent / Entrée** | `"Geist Mono"` / `"Geist"` | `13` | `"normal"` / `"medium"` | `"#F3F4F6"` | Entrée de filtre, log d'agent (`"Geist Mono"`) ou résumé (`"Geist"`) |
| **4. Trace / Badge / Métrique** | `"Geist Mono"` | `11` | `"normal"` | `"#71717A"` | `trace_id`, durée `142ms`, tokens `1 240 in / 380 out` |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#0F1110"`, `radius: 6`, `borderWidth: 1`, `borderColor: "#1F2924"`, `elevation: 0`, `padding: 16` (descriptions de section en `"Geist"`).
- **Boutons (`SuperAction`)** :
  - Primaire (`variant: "filled"`) : `fontFamily: "Geist Mono"`, `backgroundColor: "#10B981"`, **`color: "#050505"`, `iconColor: "#050505"`** (ou `"#042F2E"` — jamais de blanc sur `#10B981` afin de garantir un contraste AA irréprochable > 8:1), `fontWeight: "semibold"`, `radius: 4`, `horizontalPadding: 14`, `verticalPadding: 8`.
  - Secondaire (`variant: "outlined"`) : `fontFamily: "Geist Mono"`, `backgroundColor: "#0F1110"`, `borderColor: "#1F2924"`, `borderWidth: 1`, `color: "#F3F4F6"`, `iconColor: "#10B981"`, `radius: 4`.
  - Action d'icône (`variant: "icon"`) : `iconColor: "#71717A"` avec `tooltip` précis (`"Relancer l'agent"`, `"Copier le payload"`).
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : fond `"#161A18"`, bordure `1px` `"#1F2924"`, `radius: 4`, texte `"#F3F4F6"`, `fontFamily: "Geist Mono"` pour les clés API, endpoints, paramètres d'agents et filtres de logs.
- **Collections (`ListView` / `Table` / `TreeView`)** : `styles["<listId>:item"]` avec `color: "#00000000"`, `radius: 4`, `padding: 8`, `hoverEffect: true`, et `states.selected` en `color: "#0A261E"`, `borderColor: "#10B981"`, `borderWidth: 1`.
- **Pastilles d'état (`SuperIndicator`)** : style badge télémétrique en `fontFamily: "Geist Mono"`, `fontSize: 11`, `radius: 4`, `horizontalPadding: 8`, `verticalPadding: 3` ; `RUNNING` / `OK` en `backgroundColor: "#0A2E22"`, `color: "#34D399"`, `iconColor: "#10B981"` ; `ERROR` en `backgroundColor: "#2A1215"`, `color: "#F87171"`, `iconColor: "#EF4444"`.

## 5. Layout Principles
- **Échelle d'espacement** : utilisez `4, 8, 12, 16, 20, 24` en privilégiant une densité technique serrée (`zoneFlows.*.padding: 12`, `spacing: 12`, `Card.padding: 16`, `styles["background"].padding: 0`).
- **Rayons concentriques stricts** : `Card` parente à `6px` $\rightarrow$ onglets et sous-blocs à `4px` $\rightarrow$ lignes de liste, boutons et champs à `4px` (aucun enfant ne dépasse `6px`).
- **Calibrage Desktop des collections** : `ListView` d'agents à `itemExtent: 48` (`spacing: 4`) ; `TreeView` d'appels d'outils imbriqués à `rowHeight: 32`, `indent: 18`, `headerSize: 260` ; `SuperTable` de traces à `headerRowHeight: 36`, `rowHeight: 36`.

## 6. Depth & Elevation
- **Planéité technique** : `"designSystem": "material"` avec `elevation: 0` partout. Sur un canevas `#050505`, les ombres portées sont invisibles ou boueuses : toute la profondeur provient des paliers `#050505` $\rightarrow$ `#0F1110` $\rightarrow$ `#161A18` et du trait `#1F2924`.
- **Sobriété lumineuse** : n'activez pas de halo `neon` permanent sur toutes les cartes ; laissez la vivacité du `#10B981` jouer le rôle de témoin lumineux ponctuel.

## 7. Do's and Don'ts
- **Do** : Imposer `color: "#050505"` (ou `"#042F2E"`) sur tout bouton ou badge plein `#10B981` pour une netteté maximale.
- **Do** : Aligner à droite (`textAlign: "end"`) toutes les colonnes de latence, de jetons et de coûts en `"Geist Mono"`.
- **Do** : Utiliser `SuperTreeView` ou `SuperTable` pour inspecter les étapes d'exécution d'un workflow multi-agents.
- **Do** : Renseigner des `emptyText` techniques explicites (`"Aucune trace enregistrée sur cette fenêtre temporelle"`).
- **Don't** : Ne jamais écrire en blanc `#FFFFFF` sur un fond émeraude `#10B981` (contraste insuffisant).
- **Don't** : Ne jamais arrondir les cartes à `16px` ou `20px`, ce qui détruirait le caractère instrumental de la console.
- **Don't** : Ne jamais saturer l'écran de vert émeraude sur de larges fonds de cartes (respecter le ratio 10 % d'accent).
- **Don't** : Ne jamais afficher les payloads ou synthèses d'outils sous forme d'un `textarea` libre non structuré.

## 8. Responsive & Desktop Ergonomics
- **Console Maître / Détail (Liste des runs / Inspecteur de trace)** : sur `mainLayout`, configurez `west: true`, `westSize: 320`, `resizeSides: true`, `"autoSides": []`, et `nw: "row"` si une barre globale `north` est présente.
- **Barre de télémétrie (`north`)** : 4 compteurs temps réel (`Agents actifs`, `Appels / min`, `Latence médiane`, `Taux de succès`) en `row` (`northSize: 96`, `spacing: 12`).
- **Panneaux de configuration d'agent** : bornez les formulaires à `maxWidth: "760px"` et gardez `"autoSides": []` dès qu'une zone active `scrollable: true`.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour initialiser la console sombre VoltAgent :

```json
{
  "mode": "dark",
  "accent": "#10B981",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#050505",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#0F1110",
      "radius": 6,
      "borderWidth": 1,
      "borderColor": "#1F2924",
      "elevation": 0,
      "padding": 16
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 4,
      "padding": 8,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#0A261E",
            "borderColor": "#10B981",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "section-desc": {
      "type": "value",
      "label": "Graphe d'orchestration",
      "text": "Exécution temps réel des sous-agents et outils",
      "fontFamily": "Geist",
      "fontSize": 14,
      "color": "#F3F4F6"
    },
    "kpi-latency": {
      "type": "value",
      "label": "LATENCE P95",
      "text": "142ms",
      "fontFamily": "Geist Mono",
      "fontSize": 22,
      "fontWeight": "bold",
      "color": "#F3F4F6"
    },
    "agent-status": {
      "type": "indicator",
      "icon": "bolt",
      "label": "RUNNING · 1240 tok",
      "fontFamily": "Geist Mono",
      "fontSize": 11,
      "color": "#34D399",
      "iconColor": "#10B981",
      "backgroundColor": "#0A2E22",
      "borderColor": "#1F2924",
      "borderWidth": 1,
      "radius": 4,
      "horizontalPadding": 8,
      "verticalPadding": 3
    }
  }
}
```
