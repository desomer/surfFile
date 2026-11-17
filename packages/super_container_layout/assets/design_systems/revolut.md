---
name: "Revolut"
slug: "revolut"
category: "fintech"
tagline: "Néo-banque sombre ultra-fluide aux cartes obsidienne galbées et accent cobalt électrique."
description: "Interface néo-bancaire contemporaine construite sur un fond obsidienne (#0B0D12), des cartes galbées sans surcharge visuelle (#161922, rayon 18px) et un bleu cobalt vif (#0075EB). Idéal pour les super-apps financières, le suivi budgétaire temps réel, le trading d'actifs, la gestion de cartes et les consoles fintech grand public ou pro."
mode: "dark"
accent: "#0075EB"
canvasColor: "#0B0D12"
surfaceColor: "#161922"
textColor: "#F7F8FA"
mutedTextColor: "#8B93A7"
borderColor: "#242938"
cardRadius: 18
surfaceSystem: "material"
fontFamily: "Inter"
---

# Revolut — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
Cette esthétique néo-bancaire conjugue vélocité visuelle et épure nocturne. Sur un canevas obsidienne `#0B0D12`, les modules `#161922` adoptent un galbe prononcé (`18px`) et une bordure discrète `#242938` qui éliminent toute rigidité bureaucratique. Le contraste franc du blanc glacé `#F7F8FA` fait jaillir les soldes et variations instantanées, tandis que le bleu cobalt `#0075EB` guide l'œil avec précision vers les actions transactionnelles essentielles.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas obsidienne** | `#0B0D12` | `styles["background"].color` — fond sombre principal (`padding: 0`) |
| **Surface carte galbée** | `#161922` | `Card` de comptes, widgets analytiques, cartes virtuelles et listes |
| **Sous-surface contrôle** | `#1E2230` | Barre d'onglets segmentée, champs `input` et pastilles neutres |
| **Bordure ardoise nuit** | `#242938` | Filet `1px` discret assurant la tenue géométrique des cartes |
| **Blanc glacé primaire** | `#F7F8FA` | Soldes principaux, titres de cartes et libellés de marchands |
| **Gris acier secondaire** | `#8B93A7` | Catégories de dépenses, heures de paiement et sous-titres |
| **Accent Bleu Cobalt** | `#0075EB` | Racine `"accent"`, CTA primaire `filled`, filtre actif et focus |
| **Surface sélectionnée** | `#13294B` | Fond `states.selected` des transactions avec bordure `#0075EB` |
| **Gain / Remboursement** | `#10B981` | Crédit entrant ou performance positive sur pastille `#0F2E24` |
| **Débit rejeté / Blocage** | `#F04438` | Paiement refusé ou gel de sécurité sur pastille `#30161B` |

## 3. Typography Rules
Utilisez **`"Inter"`** sur toutes les cartes sombres néo-bancaires, soldes, montants et libellés de marchands pour garantir des chiffres géométriques à fort impact visuel, complété par **`"JetBrains Mono"`** (ou **`"Consolas"`**) pour les numéros de carte masqués (`•••• 4821`), IBANs et tickers boursiers.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Solde / KPI majeur** | `"Inter"` | `26` | `"bold"` | `"#F7F8FA"` | Solde disponible, valeur de portefeuille ou en-tête de vue |
| **2. Titre de carte / Section** | `"Inter"` | `17` | `"semibold"` | `"#F7F8FA"` | Titre de `Card` (`Transactions`, `Cartes actives`, `Analytique`) |
| **3. Marchand / Montant ligne** | `"Inter"` | `14` | `"medium"` | `"#F7F8FA"` | Nom du commerçant, montant de transaction, champ `input` |
| **4. Chiffres carte / IBAN / Métadonnée** | `"JetBrains Mono"` / `"Inter"` | `12` | `"normal"` | `"#8B93A7"` | Carte `•••• 4821`, IBAN en `Consolas` / `JetBrains Mono`, ou heure `14:32` |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#161922"`, `radius: 18`, `borderWidth: 1`, `borderColor: "#242938"`, `elevation: 0`, `padding: 20`.
- **Boutons (`SuperAction`)** :
  - Primaire (`variant: "filled"`) : `fontFamily: "Inter"`, `backgroundColor: "#0075EB"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `fontWeight: "semibold"`, `radius: 99` (pilule dynamique) ou `12`, `horizontalPadding: 18`, `verticalPadding: 10` (contraste AA net).
  - Secondaire (`variant: "tonal"`) : `fontFamily: "Inter"`, `backgroundColor: "#1E2230"`, `color: "#F7F8FA"`, `iconColor: "#F7F8FA"`, `radius: 99` (ex. `"Ajouter des fonds"`, `"Échanger"`).
  - Action rapide (`variant: "icon"`) : `iconColor: "#8B93A7"` (ou `"#0075EB"`) avec `tooltip` explicite (`"Geler la carte"`).
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"` (ou `"JetBrains Mono"` pour un IBAN), fond `"#1E2230"`, bordure `1px` `"#242938"`, `radius: 12`, `color: "#F7F8FA"`, `placeholder` direct (`"Rechercher un marchand ou un montant"`).
- **Collections (`ListView` / `Table`)** : lignes de transactions nettes avec `itemExtent: 56` ; `styles["<listId>:item"]` en `color: "#00000000"`, `radius: 12`, `padding: 12`, `hoverEffect: true`, et `states.selected` en `color: "#13294B"`, `borderColor: "#0075EB"`, `borderWidth: 1`.
- **Pastilles (`SuperIndicator`)** : `radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4` ; `Actif` / `Complété` (`#0F2E24` / `#34D399`), `En cours` (`#13294B` / `#60A5FA`), `Refusé` (`#30161B` / `#F87171`).

## 5. Layout Principles
- **Échelle d'espacement** : respectez `4, 8, 12, 16, 20, 24` (`styles["background"].padding: 0`, `zoneFlows.*.padding: 16`, `zoneFlows.*.spacing: 16`, `Card.padding: 20`, avec `padding >= spacing`).
- **Rayons concentriques** : `Card` extérieure galbée à `18px` $\rightarrow$ sous-panneaux, champs et lignes de transactions à `12px` $\rightarrow$ petits badges internes à `8px` ou pilules `99px`.
- **Calibrage Desktop des collections** : `ListView` des transactions réglée sur **`itemExtent: 56`** (`spacing: 4`) avec marchand + catégorie à gauche et montant + statut alignés à droite (`"end"`) ; `SuperTable` à `headerRowHeight: 38`, `rowHeight: 40`.

## 6. Depth & Elevation
- **Surfaces lisses sans bruit visuel** : `"designSystem": "material"` avec `elevation: 0` sur toutes les cartes ; l'écart de luminance `#0B0D12` $\rightarrow$ `#161922` $\rightarrow$ `#1E2230` suffit à sculpter les volumes avec modernité.
- **Discipline d'effets** : n'activez ni `liquidGlass`, ni `neumorphism`, ni halos `neon` afin de préserver la lisibilité immédiate des montants.

## 7. Do's and Don'ts
- **Do** : Calibrer les listes de flux financiers sur `itemExtent: 56` avec un alignement droit irréprochable des montants.
- **Do** : Conserver des cartes `#161922` épurées (`radius: 18`) limitant chaque bloc à une fonction claire (solde, carte, flux, analytique).
- **Do** : Utiliser un unique CTA `"filled"` `#0075EB` (`color: "#FFFFFF"`) accompagné d'actions secondaires `"tonal"` `#1E2230`.
- **Do** : Configurer un `emptyText` soigné en français (`"Aucune transaction enregistrée sur cette carte"`).
- **Don't** : Ne jamais surcharger les lignes de transactions de bordures lourdes au repos (`color: "#00000000"` dans la carte parente suffit).
- **Don't** : Ne jamais imbriquer des cartes arrondies à `18px` dans d'autres cartes à `18px`.
- **Don't** : Ne jamais concaténer marchand, date et montant dans un seul `SuperValue`.
- **Don't** : Ne jamais utiliser un `textarea` multiligne pour lister des dépenses ou des plafonds de carte.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Flux de transactions / Reçu & Contrôles carte)** : `mainLayout` avec `west: true`, `westSize: 340`, `resizeSides: true` et `"autoSides": []` ; la zone `center` présente le détail du marchand, la répartition analytique ou les réglages de sécurité de la carte sélectionnée.
- **Bandeau Synthèse (`north`)** : 3 à 4 cartes galbées (`Solde total`, `Dépenses du mois`, `Cashback cumulé`, `Cartes actives`) en `row` (`northSize: 116`, `spacing: 16`).
- **Panneaux de plafonds et virements** : bornez la largeur du formulaire à `maxWidth: "700px"` (`crossAxisAlignment: "center"`) et maintenez `"autoSides": []` sur tout layout défilant.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour déployer l'interface sombre Revolut :

```json
{
  "mode": "dark",
  "accent": "#0075EB",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#0B0D12",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#161922",
      "radius": 18,
      "borderWidth": 1,
      "borderColor": "#242938",
      "elevation": 0,
      "padding": 20
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 12,
      "padding": 12,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#13294B",
            "borderColor": "#0075EB",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "balance-total": {
      "type": "value",
      "label": "Solde disponible",
      "text": "14 820,50 €",
      "fontFamily": "Inter",
      "fontSize": 26,
      "fontWeight": "bold",
      "color": "#F7F8FA"
    },
    "card-digits": {
      "type": "value",
      "label": "Carte virtuelle",
      "text": "•••• 4821",
      "fontFamily": "JetBrains Mono",
      "fontSize": 12,
      "color": "#8B93A7"
    }
  }
}
```
