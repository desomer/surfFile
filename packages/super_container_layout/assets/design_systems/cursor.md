---
name: "Cursor"
slug: "cursor"
category: "developer-tools"
tagline: "Esthétique IDE assisté par IA, panneaux fusain compacts et densité technique 32–36px"
description: "Environnement sombre de précision combinant un canevas #0C0C0D, des volets d'édition fusain #161618 scindés par des filets #27272A et un bleu électrique #3B82F6 d'orchestration IA. Taillé pour les explorateurs de fichiers, studios d'agents, éditeurs de règles, diffs techniques et inspecteurs de code."
mode: "dark"
accent: "#3B82F6"
canvasColor: "#0C0C0D"
surfaceColor: "#161618"
textColor: "#ECECEE"
mutedTextColor: "#8E8E93"
borderColor: "#27272A"
cardRadius: 8
surfaceSystem: "material"
fontFamily: "Inter"
---

# Cursor — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette direction visuelle reproduit le **confort focalisé d'un IDE de nouvelle génération piloté par l'IA** : compact, modulaire, silencieux et conçu pour de longues sessions sur grand écran. Le fond zinc abyssal (`#0C0C0D`) accueille des volets d'outils et d'inspection fusain (`#161618`) articulés par des séparateurs discrets (`#27272A`). Chaque pixel privilégie la densité informationnelle (`32` à `36px` par ligne d'arbre ou de table) et la lisibilité instantanée des chemins, jetons et diagnostics.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les environnements de développement assistés par IA modernes, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#0C0C0D` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#161618` | `styles["<cardId>"].color` (volets explorateur, chat agent, inspecteur) |
| **Elevated / Secondary Surface** | `#1E1E22` | Zone de prompt, barre d'onglets d'éditeur (`tabBarStyle`), blocs contexte |
| **Primary Text** | `#ECECEE` | `SuperValue` noms de fichiers, symboles actifs, valeurs principales |
| **Muted / Secondary Text** | `#8E8E93` | `SuperValue` chemins relatifs, compteurs de tokens, raccourcis clavier |
| **Hairline / Border** | `#27272A` | `borderColor` (`borderWidth: 1`) et traits `SuperSeparator` |
| **Brand Accent + On-Accent** | `#3B82F6` / `#08101E` | Racine `"accent"`, focus actif (ou bouton `#2563EB` avec texte `#FFFFFF` AA) |
| **Selected Row State** | `#1D283A` | `styles["<listId>:item"].states.selected.style.color` (bordure `#3B82F6`) |
| **Semantic Success (Diff +)** | `#22C55E` | `SuperIndicator` ajouts / tests passants (fond `#0F291A`, texte `#4ADE80`) |
| **Semantic Warning (Modifié)** | `#EAB308` | `SuperIndicator` fichiers modifiés / lint (fond `#29210B`, texte `#FACC15`) |
| **Semantic Error (Diff -)** | `#EF4444` | `SuperIndicator` erreurs compilation / suppressions (fond `#2C1215`, texte `#F87171`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Inter"`** pour les panneaux d'IDE, titres de volets et contrôles d'interface ; **`"JetBrains Mono"`** (ou `"Cascadia Mono"`) pour les badges `@file`, chemins (`src/services/router.dart`), numéros de lignes, diffs (`+48 -12`), étiquettes de modèles IA et métriques de latence.
- **Sobriété des tailles** : éviter les titres surdimensionnés ; un en-tête d'IDE plafonne à `18`–`20px` pour préserver l'espace vertical de travail.

| Niveau (`SuperValue`) | `fontSize` | `fontWeight` | `color` | Famille conseillée | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `20`–`22` | `"semibold"` | `#ECECEE` | `"Inter"` | En-tête d'espace de travail ou KPI d'indexation |
| **2. Section / Pane Title** | `14`–`15` | `"semibold"` | `#ECECEE` | `"Inter"` | Titre de volet (`Explorateur`, `Agent`, `Diagnostics`) |
| **3. Body / Tree Entry** | `13` | `"normal"` | `#ECECEE` | `"Inter"` / `"JetBrains Mono"` | Entrée d'arbre, cellule de table, champ de prompt |
| **4. Label / Code Meta** | `11` | `"normal"` | `#8E8E93` | `"JetBrains Mono"` | Badge `@file`, chemin dossier, ligne `:142`, diff `+18/-4` |

## 4. Component Stylings
- **Panes & Cards (`Card`)** : `designSystem: "material"`, `color: "#161618"`, `radius: 8`, `borderWidth: 1`, `borderColor: "#27272A"`, `elevation: 0`, `padding: 12` ou `16`.
- **Boutons (`SuperAction`)** :
  - *Primaire* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Inter"`, `backgroundColor: "#2563EB"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (ou `backgroundColor: "#3B82F6"` avec `color: "#08101E"`, `iconColor: "#08101E"` pour verrouiller un contraste AA > 5:1), `radius: 6`, `fontSize: 12`, `fontWeight: "semibold"`, `horizontalPadding: 12`, `verticalPadding: 7`.
  - *Secondaire (contexte / action rapide)* : `variant: "outlined"`, `fontFamily: "Inter"`, `backgroundColor: "#1E1E22"`, `borderColor: "#323238"`, `borderWidth: 1`, `color: "#ECECEE"`, `iconColor: "#8E8E93"`, `radius: 6`.
  - *Barre d'outils d'éditeur* : `kind: "icon"`, `variant: "icon"`, `iconSize: 16`, `iconColor: "#8E8E93"`, `tooltip` obligatoire (`"Actualiser l'index"`, `"Ouvrir le terminal"`).
- **Champs & Composer (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"`, `field.fillColor: "#111113"`, `field.borderColor: "#27272A"`, `field.radius: 6`, `color: "#ECECEE"`, `dense: true`. Sélecteurs de mode (`Agent / Ask / Edit`) en `choice` `variant: "segmented"`.
- **Arbres, Listes & Tables (`TreeView`, `ListView`, `Table`)** :
  - `<listId>:item` : `color: "#00000000"`, `radius: 6`, `paddingInsets: [4, 8, 4, 8]`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#1F1F23"`. Sélection `states.selected` en `#1D283A` avec filet `1px` `#3B82F6`.
- **Badges contextuels `@file` & étiquettes modèle (`SuperIndicator`)** : format chip compact (`radius: 5`, `fontSize: 11`, `fontFamily: "JetBrains Mono"`, `backgroundColor: "#1E1E22"`, `borderColor: "#323238"`, `borderWidth: 1`, `horizontalPadding: 6`, `verticalPadding: 2`).

## 5. Layout Principles
- **Échelle d'espacement IDE** : `4, 8, 12, 16, 20`. `styles["background"].padding: 0` ; gouttières resserrées (`zoneFlows.*.spacing: 8`, `padding: 8` ou `12`) pour maximiser la surface d'inspection.
- **Rayons concentriques** : Volet `Card` `radius: 8` $\rightarrow$ Onglet / Champ / Bouton / Ligne `radius: 6` $\rightarrow$ Chip `@context` `radius: 5`.
- **Calibrage ultra-compact Desktop** : `SuperTreeView` avec `rowHeight: 32`, `indent: 16`, `headerSize: 240` ; `ListView` avec `itemExtent: 36` (1 ligne) ou `48` (2 lignes), `spacing: 2` ; `SuperTable` avec `headerRowHeight: 32` et `rowHeight: 34`.

## 6. Depth & Elevation
- **Docking plat multi-volets** : `designSystem: "material"` et `elevation: 0` sur tous les panneaux ancrés. L'architecture en volets juxtaposés repose uniquement sur l'écart `#0C0C0D` / `#161618` et les bordures `1px` `#27272A`.
- **Palette flottante uniquement** : ombre sèche (`opacity: 0.5`, `blur: 24`, `dy: 8`) réservée à une éventuelle boîte d'invite centrale détachée.

## 7. Do's and Don'ts
- **Do** : Privilégier une disposition multi-volets redimensionnable (`west` explorateur + `center` éditeur/table + `east` inspecteur/assistant).
- **Do** : Afficher les métadonnées techniques (`@file`, extensions, diffs, étiquettes de modèles) en `"JetBrains Mono"` (ou `"Cascadia Mono"`) `11px`.
- **Do** : Conserver des hauteurs de lignes denses (`32`–`36px`) adaptées au pointeur souris et à la navigation clavier.
- **Do** : Renseigner explicitement les coins du `SuperLayout` (`nw`, `ne`, `sw`, `se` sur `"row"` ou `"column"`) dès que `north`/`south` croise `west`/`east`.
- **Don't** : Ne jamais gaspiller l'espace avec des `padding: 32` ou des `itemExtent: 72` sur un outil développeur.
- **Don't** : Ne jamais utiliser d'effets décoratifs `neumorphism` ou `neon` criards.
- **Don't** : Ne jamais activer `"autoSides"` sur un volet `west` ou `east` contenant une `TreeView` ou `ListView`.
- **Don't** : Ne jamais laisser un bouton icône de barre d'outils sans `tooltip`.

## 8. Responsive & Desktop Ergonomics
- **Workbench 3 colonnes (`mainLayout`)** : `west: true` (`westSize: 260`, `TreeView` ou `ListView` de navigation), `center` (`expandSlots: true`, vue principale ou `SuperTab` multi-fichiers) et `east: true` optionnel (`eastSize: 320`–`360`, panneau d'inspection ou de session IA), avec `resizeSides: true` et `"autoSides": []`.
- **Barre d'état inférieure (`south`)** : hauteur compacte `southSize: 28`–`32` (`zoneAxes.south: "row"`) regroupant branche Git, encodage et compteur d'erreurs.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "dark",
  "accent": "#3B82F6",
  "components": {
    "pane-title": {
      "type": "value",
      "text": "Agent Composer",
      "fontFamily": "Inter",
      "fontSize": 14,
      "fontWeight": "semibold",
      "color": "#ECECEE"
    },
    "badge-file-context": {
      "type": "indicator",
      "icon": "code",
      "label": "@router.dart +48/-12",
      "fontFamily": "JetBrains Mono",
      "fontSize": 11,
      "backgroundColor": "#1E1E22",
      "borderColor": "#323238",
      "borderWidth": 1,
      "color": "#ECECEE",
      "iconColor": "#3B82F6",
      "radius": 5,
      "horizontalPadding": 6,
      "verticalPadding": 2
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#0C0C0D",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#161618",
      "radius": 8,
      "borderWidth": 1,
      "borderColor": "#27272A",
      "elevation": 0,
      "padding": 12
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 6,
      "paddingInsets": [4, 8, 4, 8],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#1F1F23",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#1D283A",
            "borderWidth": 1,
            "borderColor": "#3B82F6"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
