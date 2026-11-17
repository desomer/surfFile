---
name: "Framer"
slug: "framer"
category: "design-creative"
tagline: "Mode sombre vitrine à contraste absolu, cartes carbone #111111 et accent électrique #0099FF."
description: "Esthétique dark-mode contemporaine posée sur un noir profond #000000, structurée en blocs bento #111111 sertis d'un filet #222222 et dynamisée par un bleu électrique #0099FF. Idéale pour les dashboards créatifs, plateformes IA/SaaS, portfolios interactifs et consoles de publication."
mode: "dark"
accent: "#0099FF"
canvasColor: "#000000"
surfaceColor: "#111111"
textColor: "#FFFFFF"
mutedTextColor: "#888888"
borderColor: "#222222"
cardRadius: 14
surfaceSystem: "material"
fontFamily: "Inter"
---

# Framer — DESIGN.md

> *Note : Ce guide constitue une analyse esthétique et technique indépendante, conçue comme source d'inspiration de tokens pour `super_container_layout` sans affiliation ni reproduction de documentation propriétaire.*

## 1. Visual Theme & Atmosphere
Le thème **Framer** cultive une présence nocturne spectaculaire mais disciplinée : un noir pur `#000000` absorbe l'arrière-plan tandis que les modules fonctionnels émergent sous forme de tuiles carbone `#111111` aux contours ciselés (`1px #222222`, `radius: 14`). Le contraste maximal avec la typographie blanc pur `#FFFFFF` confère aux chiffres clés et aux titres une netteté d'écran OLED, adoucie par un gris neutre `#888888` pour les métadonnées et électrisée par des ponctuations franches en bleu `#0099FF`.

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas OLED** | `#000000` | `styles["background"].color` (padding `0`) |
| **Surface Bento primaire** | `#111111` | `styles["<cardId>"].color`, panneaux et cartes analytiques |
| **Surface élevée / Champ** | `#1A1A1A` | Lignes au survol, champs de saisie, boutons secondaires tonals |
| **Texte primaire** | `#FFFFFF` | Titres d'impact, métriques KPI, valeurs actives (`SuperValue`) |
| **Texte secondaire (Muted)** | `#888888` | Libellés secondaires, axes, horodatages, descriptions |
| **Accent électrique** | `#0099FF` | `accent` racine, CTA primaire `SuperAction`, contour actif |
| **Surface sélectionnée** | `#0A2540` | Fond `states.selected` des items de liste et onglets actifs |
| **Bordure carbone** | `#222222` | `borderColor` structurel (`1px`) indispensable en mode noir pur |
| **Statuts (Live / Warn / Err)** | `#00CC88` / `#FFAA00` / `#FF3366` | Pastilles `SuperIndicator` sur fonds sombres `#082B20` / `#2E2005` / `#330A16` |

## 3. Typography Rules
S'appuyer exclusivement sur **`"Inter"`** (repli `"Segoe UI"`) en associant des titres display audacieux (`24`–`26px`, `"bold"`, resserrement optique `letterSpacing: -0.5`) qui tranchent sur le noir profond `#000000` à un corps de texte net et nerveux (`13`–`14px`).

| Niveau `SuperValue` | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Display / KPI Majeur** | `"Inter"` | `24`–`26` | `"bold"` | `#FFFFFF` | En-tête vitrine, chiffre clé de performance ou compteur live |
| **2. Titre de Carte / Section** | `"Inter"` | `16`–`18` | `"semibold"` | `#FFFFFF` | En-tête de tuile bento, de panneau maître ou d'`ApplicationBar` |
| **3. Corps / Champ / Ligne** | `"Inter"` | `13`–`14` | `"normal"` (`"medium"` sur le titre de ligne) | `#FFFFFF` | Attributs métier atomiques, entrées de `ListView` et `Table` |
| **4. Métadonnée / Légende** | `"Inter"` | `11`–`12` | `"normal"` | `#888888` | Sous-titres, étiquettes secondaires, pourcentages d'évolution |

## 4. Component Stylings
- **Cartes Bento (`Card` / `IterableContent`)** : `designSystem: "material"`, `color: "#111111"`, `radius: 14`, `padding: 20`, `borderWidth: 1`, `borderColor: "#222222"`, `elevation: 0`. Sur fond `#000000`, la bordure `#222222` est essentielle pour dessiner la géométrie de chaque carte.
- **Boutons (`SuperAction`)** :
  - *Primaire (`variant: "filled"`)* : `fontFamily: "Inter"`, `backgroundColor: "#0099FF"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"` (contraste AA élevé), `radius: 10`, `fontWeight: "semibold"`, `horizontalPadding: 16`, `verticalPadding: 10`.
  - *Secondaire (`variant: "outlined"` ou `"tonal"`)* : `backgroundColor: "#1A1A1A"`, `borderColor: "#2A2A2A"`, `borderWidth: 1`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 10`.
  - *Tertiaire (`variant: "text"`)* : `color: "#888888"`, `iconColor: "#888888"`.
- **Champs & Contrôles (`SuperValue`)** : conserver l'atomicité stricte (`1 attribut = 1 SuperValue`), `color: "#FFFFFF"`, `placeholder` discret. Utiliser `switch` pour les activations instantanées de publication ou d'aperçu.
- **Collections (`<listId>:item` & `SuperTable`)** : `color: "#141414"`, `radius: 10`, `padding: 12`, `hoverEffect: true`, `hoverColor: "#1E1E1E"`. `states.selected` : `color: "#0A2540"`, `borderWidth: 1`, `borderColor: "#0099FF"`.
- **Indicateurs (`SuperIndicator`)** : capsules sombres à texte lumineux (`radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4`, ex. statut publié `backgroundColor: "#0A2540"`, `color: "#4DB8FF"`, `iconColor: "#4DB8FF"`).

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding` reste à `0` ; régler `zoneFlows.*.padding` sur `16` et `spacing` sur `12` ou `16` afin de découper nettement les tuiles `#111111` sur le fond `#000000`.
- **Rayons concentriques** : cartes principales à `radius: 14` (`padding: 16` ou `20`), lignes de liste, boutons et champs internes à `radius: 8` ou `10`.
- **Collections Desktop** : `ListView` à `itemExtent: 54`–`62` (`spacing: 6`), `SuperTable` à `headerRowHeight: 38` et `rowHeight: 40`, `TreeView` de navigation à `rowHeight: 34`.

## 6. Depth & Elevation
En noir absolu `#000000`, les ombres portées noires sont invisibles : fixer `elevation: 0` sur `designSystem: "material"` et construire toute la profondeur par **étagement de luminance** (`#000000` fond $\rightarrow$ `#111111` carte $\rightarrow$ `#1A1A1A` sous-bloc / survol $\rightarrow$ `#222222` filet de bordure `1px`). Éviter tout mélange avec `neumorphism` ou des halos néon saturés non demandés.

## 7. Do's and Don'ts
- **Do** : Toujours associer `borderWidth: 1` et `borderColor: "#222222"` à chaque surface `#111111` pour une découpe nette sur `#000000`.
- **Do** : Exploiter des titres KPI francs (`24`–`26px`, `"bold"`, `#FFFFFF`) accompagnés d'un label `#888888` compact (`12px`).
- **Do** : Limiter le bleu `#0099FF` au bouton d'action principal et au repère de sélection actif.
- **Do** : Configurer `hoverEffect: true` et `states.selected` sur chaque `<listId>:item`.
- **Don't** : Ne jamais compter sur `elevation` seule sans `borderColor` en mode `#000000` (les cartes fusionneraient visuellement).
- **Don't** : Ne jamais utiliser de gris trop sombre (`< #707070`) pour du texte secondaire : conserver `#888888` pour le contraste AA.
- **Don't** : Ne jamais imbriquer de cartes gigognes ni placer une `Card` dans `list.template.placements`.
- **Don't** : Ne jamais étirer un bouton primaire `#0099FF` sur toute la largeur d'un grand panneau Desktop.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail Créatif** : `west: true`, `westSize: 310`, `resizeSides: true`, `autoSides: []`. Le panneau maître `#111111` présente les projets ou pages tandis que la zone `center` (`expandSlots: true`) affiche l'aperçu détaillé ou les onglets `SuperTab`.
- **Grille Bento Analytique** : bande `north` de 3 à 4 tuiles KPI (`northSize: 112`, `zoneAxes.north: "row"`, `spacing: 12`, `expandSlots: true`) surplombant un graphique `SuperChart` et une `SuperTable` en `center`.
- **Formulaires de déploiement / réglages** : carte centrale bornée à `maxWidth: "740px"` (`crossAxisAlignment: "center"`), `scrollable: true` et `autoSides: []`.

## 9. Agent Prompt Guide (super_container_layout)
```json
{
  "mode": "dark",
  "accent": "#0099FF",
  "components": {
    "title-display": {
      "type": "value",
      "text": "Audiences & Déploiements",
      "fontFamily": "Inter",
      "fontSize": 26,
      "fontWeight": "bold",
      "letterSpacing": -0.5,
      "color": "#FFFFFF"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#000000",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#111111",
      "radius": 14,
      "padding": 20,
      "borderWidth": 1,
      "borderColor": "#222222",
      "elevation": 0
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#141414",
      "radius": 10,
      "padding": 12,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#0A2540",
            "borderWidth": 1,
            "borderColor": "#0099FF"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
