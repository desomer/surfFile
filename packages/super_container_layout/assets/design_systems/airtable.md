---
name: "Airtable"
slug: "airtable"
category: "productivity-saas"
tagline: "Base de données opérationnelle lumineuse, grilles structurées et badges sémantiques vifs"
description: "Interface claire haute lisibilité conjuguant des surfaces blanches #FFFFFF structurées par des filets #E2E5E9, un bleu cobalt énergique #166EE1 et une signalétique par pills colorés doux. Idéale pour les applications métiers tabulaires, CRM, gestion de stocks, catalogues produits et suivis d'opérations."
mode: "light"
accent: "#166EE1"
canvasColor: "#F9FAFB"
surfaceColor: "#FFFFFF"
textColor: "#1D1F25"
mutedTextColor: "#616670"
borderColor: "#E2E5E9"
cardRadius: 10
surfaceSystem: "material"
fontFamily: "Inter"
---

# Airtable — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette esthétique transforme la **base de données relationnelle en espace de travail visuel, ordonné et accessible**. Sur un canevas clair très doux (`#F9FAFB`), les conteneurs blanc franc (`#FFFFFF`) et leurs séparateurs gris ardoise clair (`#E2E5E9`) dessinent une grille d'une précision tabulaire irréprochable. Le bleu cobalt vif (`#166EE1`) ancre les actions primaires et la sélection active, tandis que des pills sémantiques bien codifiés permettent de balayer du regard des dizaines d'enregistrements instantanément.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les plateformes opérationnelles no-code et tabulaires modernes, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#F9FAFB` | `styles["background"].color` (`padding: 0`) |
| **Primary Card Surface** | `#FFFFFF` | `styles["<cardId>"].color` (grilles de données, fiches d'enregistrement, KPI) |
| **Elevated / Secondary Surface** | `#F2F4F8` | Barres de filtres/vues, en-têtes de colonnes, `tabBarStyle` |
| **Primary Text** | `#1D1F25` | `SuperValue` cellules principales, titres de vues, montants |
| **Muted / Secondary Text** | `#616670` | `SuperValue` noms de colonnes, compteurs d'enregistrements, unités |
| **Hairline / Border** | `#E2E5E9` | `borderColor` (`borderWidth: 1`), grilles `SuperTable` et `SuperSeparator` |
| **Brand Accent + On-Accent** | `#166EE1` / `#FFFFFF` | Racine `"accent"`, `SuperAction` primaire `"filled"` (contraste AA conforme) |
| **Selected Row State** | `#EBF3FE` | `styles["<listId>:item"].states.selected.style.color` (bordure `#166EE1`) |
| **Semantic Success** | `#0B8A4D` | `SuperIndicator` livré / approuvé (fond pill `#DDF7E8`, texte `#086638`) |
| **Semantic Warning** | `#D97706` | `SuperIndicator` en cours / révision (fond pill `#FEF0C7`, texte `#9A5003`) |
| **Semantic Error** | `#DC2626` | `SuperIndicator` bloqué / en retard (fond pill `#FEE4E2`, texte `#B42318`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Inter"`** pour une lisibilité optimale à `13px` dans les cellules denses, barres de vues et formulaires (repli `"Segoe UI"`) ; **`"Consolas"`** ou **`"JetBrains Mono"`** pour les références SKU, codes-barres et identifiants d'enregistrements.
- **Discipline tabulaire** : un seul attribut métier par `SuperValue` ; textes et catégories alignés à `"start"`, quantités, budgets et pourcentages alignés à `"end"`.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | `letterSpacing` | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `"Inter"` | `22`–`24` | `"bold"` | `#1D1F25` | `-0.3` | Titre de base métier ou chiffre clé d'une carte KPI |
| **2. Section / Card Title** | `"Inter"` | `16` | `"semibold"` | `#1D1F25` | `-0.1` | Titre de vue (`Inventaire actif`), entête d'inspecteur |
| **3. Body / Field Value** | `"Inter"` | `13` | `"normal"` / `"medium"` | `#1D1F25` | `0.0` | Cellule de `SuperTable`, champ de fiche détail |
| **4. Label / SKU / Metadata** | `"Inter"` / `"Consolas"` | `11`–`12` | `"medium"` | `#616670` | `0.2` | En-tête de colonne, SKU/ID (`Consolas` / `JetBrains Mono`) |

## 4. Component Stylings
- **Cards & Data Containers (`Card`)** : `designSystem: "material"`, `color: "#FFFFFF"`, `radius: 10`, `borderWidth: 1`, `borderColor: "#E2E5E9"`, `elevation: 0`, `padding: 16` (`padding: 12` autour d'une `SuperTable` plein cadre pour maximiser l'espace utile).
- **Boutons (`SuperAction`)** :
  - *Primaire* : `variant: "filled"`, `kind: "textAndIcon"`, `icon: "add"`, `fontFamily: "Inter"`, `backgroundColor: "#166EE1"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 8`, `fontSize: 13`, `fontWeight: "semibold"`, `horizontalPadding: 14`, `verticalPadding: 8`.
  - *Secondaire (barre de vues/filtres)* : `variant: "outlined"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#D0D5DD"`, `borderWidth: 1`, `color: "#1D1F25"`, `iconColor: "#616670"`, `radius: 8` (ex. `"Filtrer"`, `"Trier"`, `"Exporter"`).
  - *Tertiaire / Icône* : `variant: "text"` ou `variant: "icon"`, `color: "#616670"`, `iconColor: "#616670"`, `tooltip` explicite.
- **Champs & Filtres (`SuperValue`)** : `mode: "input"` avec `field.fillColor: "#FFFFFF"`, `field.borderColor: "#D0D5DD"`, `field.radius: 8`, `color: "#1D1F25"`. Exploiter `choice` en `variant: "filterChip"` ou `"segmented"` dans la barre d'outils pour filtrer rapidement les statuts.
- **Tables & Listes (`SuperTable` & `<listId>:item`)** :
  - `SuperTable` : `headerRowHeight: 36`, `rowHeight: 36`, colonne principale `fillPercent: 100`, colonnes statut/montant fixes (`100` à `130`).
  - `ListView` (`<listId>:item`) : `color: "#FFFFFF"`, `radius: 8`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#F2F5F9"`, et `states.selected` en `#EBF3FE` + bordure `1px` `#166EE1`.
- **Pills de catégorie/statut (`SuperIndicator`)** : `radius: 999`, `fontSize: 11`, `fontWeight: "semibold"`, `horizontalPadding: 9`, `verticalPadding: 3`, `iconSize: 13`, pilotés dynamiquement via `states.binding` + `states.named` sur le champ statut du repository JSON.

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding: 0` ; `zoneFlows.*.padding: 12` ou `16`, `spacing: 12`.
- **Rayons concentriques** : Panneau / Carte `radius: 10` $\rightarrow$ Barre d'outils / Bouton / Champ / Ligne `radius: 8` $\rightarrow$ Pill `SuperIndicator` `radius: 999`.
- **Densité opérationnelle calibrée** : `SuperTable` compacte (`headerRowHeight: 36`, `rowHeight: 36`) permettant d'afficher 15 à 20 enregistrements sans défilement excessif ; `ListView` latérale de vues avec `itemExtent: 40`–`48`, `spacing: 4`.

## 6. Depth & Elevation
- **Surface Material structurée** : `designSystem: "material"`, `elevation: 0` sur les grilles et panneaux latéraux, `elevation: 0` ou ombre très légère (`opacity: 0.05`, `blur: 10`, `dy: 2`) sur les cartes KPI en entête.
- **Hiérarchie par bordures fines** : la lisibilité des données provient des filets `#E2E5E9` et du fond d'en-tête `#F2F4F8`, jamais d'ombres lourdes ni d'effets translucides.

## 7. Do's and Don'ts
- **Do** : Placer une barre d'outils horizontale structurée (recherche + `filterChip` + actions `"Filtrer"` / `"Nouvel enregistrement"`) en zone `north` au-dessus de la `SuperTable`.
- **Do** : Utiliser `states.binding` et `states.named` sur `SuperIndicator` pour colorer automatiquement les statuts métier.
- **Do** : Associer la sélection d'une ligne de `SuperTable` ou `ListView` à une fiche d'inspection détaillée via les liaisons `[?]`.
- **Do** : Garder `color: "#FFFFFF"` sur le bouton primaire `#166EE1`.
- **Don't** : Ne jamais utiliser des hauteurs de ligne géantes (`rowHeight > 48`) qui cassent la vision d'ensemble tabulaire.
- **Don't** : Ne jamais concaténer plusieurs colonnes métier dans un seul `SuperValue` texte.
- **Don't** : Ne jamais multiplier les boutons `"filled"` bleus dans chaque ligne de table (utiliser des icônes discrètes au survol).
- **Don't** : Ne jamais activer `"autoSides"` sur une zone contenant une `SuperTable` ou une `ListView` extensible.

## 8. Responsive & Desktop Ergonomics
- **Grille Maître + Inspecteur latéral (`mainLayout`)** : table opérationnelle principale en `center` (`expandSlots: true`) accompagnée d'un volet `west` de navigation de vues (`westSize: 240`–`280`) ou d'un inspecteur `east` de fiche détaillée (`eastSize: 340`–`380`, `resizeSides: true`, `"autoSides": []`).
- **Bandeau KPI supérieur** : 4 cartes synthétiques en `north` (`zoneAxes.north: "row"`, `expandSlots: true`, `spacing: 12`, `northSize: 104`) résumant volumes, montants et alertes.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "light",
  "accent": "#166EE1",
  "components": {
    "title-main": {
      "type": "value",
      "text": "Inventaire produits",
      "fontFamily": "Inter",
      "fontSize": 22,
      "fontWeight": "bold",
      "color": "#1D1F25"
    },
    "val-sku": {
      "type": "value",
      "label": "Référence SKU",
      "binding": "produits[?].sku",
      "fontFamily": "Consolas",
      "fontSize": 12,
      "color": "#616670"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#F9FAFB",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 10,
      "borderWidth": 1,
      "borderColor": "#E2E5E9",
      "elevation": 0,
      "padding": 16
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 8,
      "paddingInsets": [6, 10, 6, 10],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#F2F5F9",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#EBF3FE",
            "borderWidth": 1,
            "borderColor": "#166EE1"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
