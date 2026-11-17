---
name: "Stripe"
slug: "stripe"
category: "fintech"
tagline: "Rigueur institutionnelle fintech, ardoise claire lumineuse et signature indigo-violet haute confiance."
description: "Architecture financière de référence associant un canevas ardoise givré (#F6F9FC), des cartes blanches nettes (#FFFFFF) à micro-élévation contrôlée, une encre marine profonde (#0A2540) et l'accent blurple (#635BFF). Idéal pour la facturation SaaS, les portails de paiement, la comptabilité, les revenus récurrents et les back-offices marchands."
mode: "light"
accent: "#635BFF"
canvasColor: "#F6F9FC"
surfaceColor: "#FFFFFF"
textColor: "#0A2540"
mutedTextColor: "#425466"
borderColor: "#E3E8EE"
cardRadius: 12
surfaceSystem: "material"
fontFamily: "Inter"
---

# Stripe — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
Ce système incarne la clarté fiduciaire et la précision logicielle d'une infrastructure de paiement mondiale. Le canevas gris-bleu glacé `#F6F9FC` fait ressortir des cartes `#FFFFFF` d'une propreté irréprochable, soulignées par un filet `#E3E8EE` et une ombre diffuse à peine perceptible (`shadowOpacity: 0.08`). L'utilisation du bleu marine profond `#0A2540` à la place du noir standard confère aux montants et aux titres une autorité calme, dynamisée avec parcimonie par l'indigo-violet `#635BFF` sur les actions clés.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas ardoise claire** | `#F6F9FC` | `styles["background"].color` — fond applicatif global (`padding: 0`) |
| **Surface carte pure** | `#FFFFFF` | `Card` de KPI, tableaux de transactions, fiches clients et formulaires |
| **Sous-surface d'en-tête** | `#F8FAFC` | En-têtes de `SuperTable`, barres de filtres et `tabBarStyle` |
| **Bordure structurelle** | `#E3E8EE` | Filet `1px` net sur toutes les cartes, séparateurs et champs |
| **Encre Marine primaire** | `#0A2540` | Titres, montants financiers, totaux et valeurs principales |
| **Ardoise secondaire** | `#425466` | Libellés de colonnes, dates, frais, descriptions et sous-titres |
| **Accent Blurple** | `#635BFF` | Racine `"accent"`, CTA primaire `filled`, onglet actif et sélection |
| **Surface sélectionnée** | `#EEF0FF` | Fond `states.selected` des lignes avec bordure `#635BFF` |
| **Paiement réussi** | `#09825D` | Statut `Payé` / `Actif` sur pastille `#DCFCE7` (texte `#065F46`) |
| **Litige / Échec** | `#DF1B41` | Statut `Échoué` / `Remboursé` ou action critique sur fond `#FFE4E8` |

## 3. Typography Rules
Utilisez **`"Inter"`** pour toute la hiérarchie financière institutionnelle afin d'obtenir des montants, titres et libellés d'une rigueur irréprochable, complété par **`"JetBrains Mono"`** (ou **`"Consolas"`**) pour les clés API (`sk_live_...`), identifiants de webhooks (`evt_...`), objets (`in_1Qx...`, `pi_3M...`) et codes tabulaires.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Montant KPI / Titre de vue** | `"Inter"` | `24` | `"bold"` | `"#0A2540"` | Volume brut, MRR, solde disponible ou titre de page |
| **2. Titre de section / Carte** | `"Inter"` | `16` | `"semibold"` | `"#0A2540"` | En-tête de `Card` (`Paiements récents`, `Échéancier`) |
| **3. Corps / Cellule / Champ** | `"Inter"` | `13` | `"normal"` / `"medium"` | `"#0A2540"` | Nom du client, montant de ligne (`medium`), champ `input` |
| **4. Clé API / Webhook / Référence** | `"JetBrains Mono"` / `"Consolas"` | `12` | `"normal"` | `"#425466"` | ID webhook `evt_...`, clé API, code devise ou référence |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#FFFFFF"`, `radius: 12`, `borderWidth: 1`, `borderColor: "#E3E8EE"`, `elevation: 1`, `shadowOpacity: 0.08`, `padding: 20`.
- **Boutons (`SuperAction`)** :
  - Primaire (`variant: "filled"`) : `fontFamily: "Inter"`, `backgroundColor: "#635BFF"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `fontWeight: "semibold"`, `radius: 8`, `horizontalPadding: 16`, `verticalPadding: 10` (contraste AA solide).
  - Secondaire (`variant: "outlined"`) : `fontFamily: "Inter"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#D8DEE6"`, `borderWidth: 1`, `color: "#0A2540"`, `iconColor: "#425466"`, `radius: 8` (ex. `"Exporter CSV"`, `"Rembourser"`).
  - Tertiaire (`variant: "text"` ou `"icon"`) : `fontFamily: "Inter"`, `color: "#635BFF"` pour un lien d'action ciblé ou `iconColor: "#425466"` pour une icône d'outil avec `tooltip`.
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"` (ou `"JetBrains Mono"` pour les clés API et secrets webhook), fond `"#FFFFFF"`, bordure `1px` `"#E3E8EE"`, `radius: 8`, `color: "#0A2540"`, `label` précis (`"Montant HT"`) et `placeholder` réaliste (`"1 250,00"`).
- **Collections (`ListView` / `Table`)** : `styles["<listId>:item"]` avec `color: "#FFFFFF"`, `radius: 8`, `padding: 10`, `hoverEffect: true`, et `states.selected` en `color: "#EEF0FF"`, `borderColor: "#635BFF"`, `borderWidth: 1`.
- **Pastilles de statut (`SuperIndicator`)** : `radius: 99` (ou `6`), `horizontalPadding: 10`, `verticalPadding: 4`, `fontWeight: "medium"` ; `Payé` (`#DCFCE7` / `#065F46`), `En attente` (`#FEF3C7` / `#92400E`), `Échoué` (`#FFE4E8` / `#BE123C`).

## 5. Layout Principles
- **Échelle d'espacement** : utilisez exclusivement `4, 8, 12, 16, 20, 24`. Gardez `styles["background"].padding` à `0`, `zoneFlows.*.padding` à `16`, `zoneFlows.*.spacing` à `16`, et `Card.padding` à `20` (`padding >= spacing`).
- **Rayons concentriques** : `Card` principale à `12px` $\rightarrow$ barres d'onglets et sous-encarts à `10px` $\rightarrow$ boutons, entrées et lignes sélectionnées à `8px`.
- **Calibrage Desktop des collections** : `SuperTable` financier à `headerRowHeight: 38`, `rowHeight: 40`, colonne client/libellé en `fillPercent: 100`, colonnes Montant/TVA/Statut à largeur fixe (`110`–`140px`) avec montants alignés à `"end"` ; `ListView` à `itemExtent: 54`.

## 6. Depth & Elevation
- **Micro-relief institutionnel** : `"designSystem": "material"` partout, `elevation: 1` et `shadowOpacity: 0.08` sur les cartes `#FFFFFF` posées sur `#F6F9FC`, combinés au filet `1px` `#E3E8EE`.
- **Hiérarchie nette** : aucune ombre sur les composants internes (tableaux, champs ou lignes de liste restent à `elevation: 0` pour préserver la finesse du trait).

## 7. Do's and Don'ts
- **Do** : Aligner systématiquement tous les montants, taxes, soldes et variations en pourcentage à droite (`textAlign: "end"`).
- **Do** : Employer `#0A2540` pour les chiffres et titres afin de préserver la signature marine caractéristique.
- **Do** : Associer chaque statut de transaction à un `SuperIndicator` lisible piloté par `states.binding` + `states.named`.
- **Do** : Fournir un `emptyText` métier précis (`"Aucune facture émise sur cette période"`).
- **Don't** : Ne jamais empiler plusieurs niveaux d'ombres portées ni dépasser `elevation: 2`.
- **Don't** : Ne jamais placer plus d'un bouton `"filled"` `#635BFF` dans la même barre d'outils.
- **Don't** : Ne jamais fusionner le libellé et le montant dans une seule chaîne `text` d'un `SuperValue`.
- **Don't** : Ne jamais utiliser un champ texte multiligne pour résumer les lignes d'une facture ou d'un abonnement.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Clients, Factures, Abonnements)** : `mainLayout` avec `west: true`, `westSize: 330`, `resizeSides: true`, `"autoSides": []` ; la sélection d'une ligne met à jour instantanément la fiche détaillée en `center` via les liaisons `[?]`.
- **Bandeau KPI Revenus (`north`)** : 4 cartes alignées en `row` (`Volume brut`, `Revenu net`, `Taux d'encaissement`, `Litiges ouverts`) avec `northSize: 112` et `spacing: 16`.
- **Formulaires de paiement / facturation** : bornez la carte centrale à `maxWidth: "740px"` (`crossAxisAlignment: "center"`), regroupez les champs courts par deux en `row` et maintenez `"autoSides": []` sur tout layout défilant.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour instaurer le design system Stripe :

```json
{
  "mode": "light",
  "accent": "#635BFF",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#F6F9FC",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 12,
      "borderWidth": 1,
      "borderColor": "#E3E8EE",
      "elevation": 1,
      "shadowOpacity": 0.08,
      "padding": 20
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 8,
      "padding": 10,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#EEF0FF",
            "borderColor": "#635BFF",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "kpi-mrr": {
      "type": "value",
      "label": "Volume net mensuel",
      "text": "128 450,00 €",
      "fontFamily": "Inter",
      "fontSize": 24,
      "fontWeight": "bold",
      "color": "#0A2540"
    },
    "webhook-id": {
      "type": "value",
      "label": "Dernier événement",
      "text": "evt_1Qx92L8fK4",
      "fontFamily": "JetBrains Mono",
      "fontSize": 12,
      "color": "#425466"
    }
  }
}
```
