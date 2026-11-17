---
name: "Mercury"
slug: "mercury"
category: "fintech"
tagline: "Banque privée nocturne aux tons indigo satinés, sérénité typographique et tables de trésorerie raffinées."
description: "Esthétique bancaire B2B feutrée articulée autour d'un canevas encre-indigo (#0D0E17), de surfaces satinées (#151726) cernées d'un filet subtil (#252840) et de pilules d'action indigo lumineux (#5266EB). Idéal pour le pilotage de trésorerie, les comptes multi-entités, la gestion des dépenses corporate et le reporting CFO."
mode: "dark"
accent: "#5266EB"
canvasColor: "#0D0E17"
surfaceColor: "#151726"
textColor: "#F4F5FA"
mutedTextColor: "#8F94B2"
borderColor: "#252840"
cardRadius: 12
surfaceSystem: "material"
fontFamily: "Inter"
---

# Mercury — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
Loin des interfaces sombres agressives ou purement noires, ce langage visuel adopte la quiétude d'un salon financier nocturne. La profondeur naît d'une base bleu nuit minéral `#0D0E17` sur laquelle reposent des panneaux satinés `#151726` délicatement détourés par `#252840`. Les espacements généreux, les soldes aériens en `#F4F5FA` et les boutons pilules indigo `#5266EB` procurent une sensation de maîtrise patrimoniale, de fluidité opérationnelle et de confiance exécutive.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas nuit indigo** | `#0D0E17` | `styles["background"].color` — fond principal apaisé (`padding: 0`) |
| **Surface satinée** | `#151726` | `Card` de comptes, graphiques de cash-flow et fiches bénéficiaires |
| **Sous-surface élevée** | `#1C1F33` | En-têtes de tableaux, champs de saisie et `tabBarStyle` |
| **Bordure indigo subtile** | `#252840` | Filet `1px` continu sur les cartes, tableaux et séparateurs |
| **Ivoire froid primaire** | `#F4F5FA` | Soldes de trésorerie, titres de cartes et montants principaux |
| **Lavande grisée muette** | `#8F94B2` | IBAN masqués, dates de valeur, catégories et légendes |
| **Accent Indigo céleste** | `#5266EB` | Racine `"accent"`, pilules d'action primaires et repères actifs |
| **Surface sélectionnée** | `#1E2447` | Fond `states.selected` des comptes ou virements sélectionnés |
| **Flux entrant / Crédit** | `#34D399` | Encaissements positifs et statut ` Approuvé ` sur fond `#112E28` |
| **Alerte / Plafond** | `#F87171` | Rejet de carte ou alerte de seuil sur pastille `#311822` |

## 3. Typography Rules
Déployez **`"Inter"`** avec une respiration soignée (`letterSpacing` léger sur les grands montants, repli `"Segoe UI"`) et **`"Consolas"`** pour les numéros de routage, BIC/IBAN et références de comptes ou virements.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Solde global / KPI** | `"Inter"` | `26` | `"semibold"` | `"#F4F5FA"` | Trésorerie consolidée, runway en mois ou en-tête de vue |
| **2. Titre de carte / Compte** | `"Inter"` | `16` | `"semibold"` | `"#F4F5FA"` | Nom de compte courant/trésorerie ou titre de panneau |
| **3. Ligne métier / Saisie** | `"Inter"` | `13` | `"normal"` / `"medium"` | `"#F4F5FA"` | Contrepartie, montant de virement (`medium`), champ `input` |
| **4. IBAN / Référence / Meta** | `"Consolas"` / `"Inter"` | `12` | `"normal"` | `"#8F94B2"` | IBAN abrégé et référence SEPA (`Consolas`), date d'exécution (`Inter`) |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#151726"`, `radius: 12`, `borderWidth: 1`, `borderColor: "#252840"`, `elevation: 0` (ou `1` avec `shadowOpacity: 0.18`), `padding: 20`.
- **Boutons (`SuperAction`)** :
  - Primaire (`variant: "filled"`) : `fontFamily: "Inter"`, `backgroundColor: "#5266EB"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `fontWeight: "semibold"`, `radius: 99` (pilule élégante signature) ou `8`, `horizontalPadding: 18`, `verticalPadding: 10` (contraste AA).
  - Secondaire (`variant: "tonal"` ou `"outlined"`) : `backgroundColor: "#1C1F33"`, `borderColor: "#252840"`, `borderWidth: 1`, `color: "#F4F5FA"`, `iconColor: "#8F94B2"`, `radius: 99`.
  - Action discrète (`variant: "icon"`) : `iconColor: "#8F94B2"` avec `tooltip` explicite (`"Télécharger le relevé PDF"`).
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : fond `"#1C1F33"`, bordure `1px` `"#252840"`, `radius: 8`, texte `"#F4F5FA"`, focus mettant l'accent sur `#5266EB`.
- **Collections (`ListView` / `Table`)** : `styles["<listId>:item"]` avec `color: "#00000000"`, `radius: 8`, `padding: 12`, `hoverEffect: true`, et `states.selected` en `color: "#1E2447"`, `borderColor: "#5266EB"`, `borderWidth: 1`.
- **Pastilles (`SuperIndicator`)** : `radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4` ; `Exécuté` (`#112E28` / `#34D399`), `En validation` (`#2B2618` / `#FBBF24`), `Carte gelée` (`#1C1F33` / `#8F94B2`).

## 5. Layout Principles
- **Échelle d'espacement** : appliquez `4, 8, 12, 16, 20, 24` en privilégiant la respiration : `styles["background"].padding: 0`, `zoneFlows.*.padding: 16` ou `20`, `zoneFlows.*.spacing: 16`, `Card.padding: 20` (`padding >= spacing`).
- **Rayons concentriques** : `Card` principale à `12px` $\rightarrow$ conteneurs d'onglets à `10px` $\rightarrow$ champs et lignes sélectionnées à `8px` (pilules réservées aux `SuperAction` et `SuperIndicator`).
- **Calibrage Desktop des collections** : `SuperTable` de trésorerie aérée à `headerRowHeight: 40`, `rowHeight: 40`, colonne bénéficiaire extensible (`fillPercent: 100`) et colonnes Compte / Date / Montant bornées (`120`–`150px`) ; `ListView` des comptes à `itemExtent: 58`.

## 6. Depth & Elevation
- **Atmosphère feutrée** : `"designSystem": "material"` exclusif ; la séparation entre `#0D0E17` et `#151726` soutenue par le filet `#252840` suffit sans recourir au `liquidGlass` ni aux lueurs `neon`.
- **Ombres mesurées** : gardez `elevation: 0` sur les listes et tableaux internes, et au plus `elevation: 1` (`shadowOpacity: 0.16`) sur les cartes KPI majeures.

## 7. Do's and Don'ts
- **Do** : Privilégier une mise en page aérée (`padding: 20`) qui met en valeur le solde principal `#F4F5FA` en poids `semibold` plutôt qu'un gras massif.
- **Do** : Aligner à droite tous les flux monétaires et soldes comptables (`textAlign: "end"`).
- **Do** : Utiliser des boutons pilules (`radius: 99`) sur l'action primaire (`"Nouveau virement"`) avec `color: "#FFFFFF"`.
- **Do** : Renseigner un `emptyText` calme et précis (`"Aucun virement en attente d'approbation"`).
- **Don't** : Ne jamais remplacer `#0D0E17` par un noir pur `#000000` ni un gris neutre terne qui effacerait la richesse indigo du thème.
- **Don't** : Ne jamais surcharger une carte avec plus de 3 tailles de police distinctes.
- **Don't** : Ne jamais imbriquer des cartes bordées `#252840` sur trois niveaux.
- **Don't** : Ne jamais synthétiser des opérations bancaires dans un champ `textarea` multiligne.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Comptes, Cartes corporate, Approbations)** : `mainLayout` avec `west: true`, `westSize: 320`, `resizeSides: true` et `"autoSides": []` ; fiche de détail ou justificatif comptable en `center` (`expandSlots: true`).
- **Synthèse de trésorerie (`north`)** : 3 à 4 cartes KPI (`Trésorerie totale`, `Rendement Treasury`, `Flux net 30j`, `Cartes actives`) en `row` (`northSize: 116`, `spacing: 16`).
- **Initiation de virement SEPA / SWIFT** : limitez le formulaire central à `maxWidth: "700px"` (`crossAxisAlignment: "center"`) et retirez tout `autoSides` dès que `scrollable: true` est actif.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour installer le thème nocturne Mercury :

```json
{
  "mode": "dark",
  "accent": "#5266EB",
  "components": {
    "val-balance": {
      "type": "value",
      "label": "Trésorerie consolidée",
      "text": "1 482 900,00 €",
      "fontFamily": "Inter",
      "fontSize": 26,
      "fontWeight": "semibold",
      "color": "#F4F5FA"
    },
    "val-iban": {
      "type": "value",
      "label": "Compte opérationnel",
      "text": "FR76 •••• •••• 4821",
      "fontFamily": "Consolas",
      "fontSize": 12,
      "color": "#8F94B2"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#0D0E17",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#151726",
      "radius": 12,
      "borderWidth": 1,
      "borderColor": "#252840",
      "elevation": 0,
      "padding": 20
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 8,
      "padding": 12,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#1E2447",
            "borderColor": "#5266EB",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
