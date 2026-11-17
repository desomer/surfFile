---
name: "Wise"
slug: "wise"
category: "fintech"
tagline: "Clarté monétaire internationale, cartes généreuses et duo iconique vert forêt & citron vif."
description: "Système visuel franc et énergique combinant un canevas neutre frais (#F2F5F7), de larges cartes blanches arrondies (rayon 16px) et le contraste identitaire vert forêt profond (#163300) / vert lime (#9FE870). Idéal pour le change multi-devises, les paiements transfrontaliers, la facturation internationale et les portefeuilles globaux."
mode: "light"
accent: "#163300"
canvasColor: "#F2F5F7"
surfaceColor: "#FFFFFF"
textColor: "#0E0F0C"
mutedTextColor: "#454745"
borderColor: "#DCE0DF"
cardRadius: 16
surfaceSystem: "material"
fontFamily: "Inter"
---

# Wise — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
Ce design system respire la transparence tarifaire et la simplicité sans frontières. Posées sur un fond gris minéral frais `#F2F5F7`, les cartes blanches `#FFFFFF` aux angles généreux (`16px`) organisent les soldes en devises et les taux de change avec une franchise immédiate. La signature chromatique repose sur le duo haute lisibilité entre le vert forêt très sombre `#163300` et le vert lime électrique `#9FE870`, produisant des appels à l'action instantanément reconnaissables et conformes aux exigences de contraste AA/AAA.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas neutre frais** | `#F2F5F7` | `styles["background"].color` — fond d'écran principal (`padding: 0`) |
| **Surface carte franche** | `#FFFFFF` | `Card` de balances multi-devises, convertisseur et listes d'opérations |
| **Sous-surface neutre** | `#EDF1F0` | Conteneurs de taux garantis, filtres et `tabBarStyle` |
| **Bordure minérale** | `#DCE0DF` | Filet `1px` net délimitant les cartes, champs et tableaux |
| **Encre carbone-olive** | `#0E0F0C` | Grands montants convertis, titres d'écran et libellés principaux |
| **Texte secondaire** | `#454745` | Taux de change `1 EUR = 1.0842 USD`, frais détaillés et dates |
| **Vert Forêt profond** | `#163300` | Racine `"accent"`, texte sur fond lime ou fond de CTA institutionnel |
| **Vert Lime vif** | `#9FE870` | Fond de CTA primaire signature (toujours associé au texte `#163300`) |
| **Surface sélectionnée** | `#E8F7DC` | Fond `states.selected` des devises ou transferts avec filet `#163300` |
| **Alerte / Blocage** | `#D92D20` | Vérification requise ou transfert annulé sur pastille `#FEE4E2` |

## 3. Typography Rules
Utilisez **`"Inter"`** avec des graisses affirmées (`"bold"`) sur les montants en devises, codes ISO (`EUR`, `GBP`, `USD`, `JPY`) et libellés nets de transfert, et **`"Consolas"`** pour les codes SWIFT/BIC, IBAN et taux de change à 4 ou 6 décimales.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Montant devise / KPI** | `"Inter"` | `26` | `"bold"` | `"#0E0F0C"` | Solde d'une balance devise, montant reçu ou titre de page |
| **2. Titre de carte / Devise** | `"Inter"` | `17` | `"semibold"` | `"#0E0F0C"` | En-tête de portefeuille, calculateur de frais ou bénéficiaire |
| **3. Corps / Champ / Ligne** | `"Inter"` | `14` | `"normal"` / `"medium"` | `"#0E0F0C"` | Libellé de transfert, saisie de montant, cellule de tableau |
| **4. SWIFT / IBAN / Taux** | `"Consolas"` / `"Inter"` | `12` | `"normal"` | `"#454745"` | Code SWIFT/IBAN et taux garanti en `"Consolas"`, frais en `"Inter"` |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#FFFFFF"`, `radius: 16`, `borderWidth: 1`, `borderColor: "#DCE0DF"`, `elevation: 0`, `padding: 20`.
- **Boutons (`SuperAction`)** :
  - Primaire signature (`variant: "filled"`) : `fontFamily: "Inter"`, deux couplages AA/AAA autorisés — soit `backgroundColor: "#9FE870"` avec **`color: "#163300"`, `iconColor: "#163300"`** (contraste > 9.5:1), soit `backgroundColor: "#163300"` avec **`color: "#9FE870"` ou `"#FFFFFF"`** ; `radius: 99`, `fontWeight: "semibold"`, `horizontalPadding: 20`, `verticalPadding: 10`.
  - Secondaire (`variant: "outlined"`) : `fontFamily: "Inter"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#163300"`, `borderWidth: 1`, `color: "#163300"`, `iconColor: "#163300"`, `radius: 99`.
  - Action tertiaire / icône (`variant: "icon"`) : `iconColor: "#454745"` avec `tooltip` clair (`"Inverser les devises"`).
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"` (ou `"Consolas"` pour un champ IBAN / SWIFT), fond `"#FFFFFF"`, bordure `1px` `"#DCE0DF"`, `radius: 10`, `color: "#0E0F0C"`, `label` explicite (`"Vous envoyez"`).
- **Collections (`ListView` / `Table`)** : `styles["<listId>:item"]` avec `color: "#FFFFFF"`, `radius: 12`, `padding: 12`, `hoverEffect: true`, et `states.selected` en `color: "#E8F7DC"`, `borderColor: "#163300"`, `borderWidth: 1`.
- **Pastilles (`SuperIndicator`)** : `radius: 99`, `horizontalPadding: 10`, `verticalPadding: 4` ; `Converti` / `Taux garanti` en `backgroundColor: "#E8F7DC"`, `color: "#163300"`, `iconColor: "#163300"` ; `En transit` en `backgroundColor: "#EDF1F0"`, `color: "#0E0F0C"`, `iconColor: "#454745"`.

## 5. Layout Principles
- **Échelle d'espacement** : utilisez `4, 8, 12, 16, 20, 24` (`styles["background"].padding: 0`, `zoneFlows.*.padding: 16`, `spacing: 16`, `Card.padding: 20`, en respectant toujours `padding >= spacing`).
- **Rayons concentriques** : `Card` extérieure généreuse à `16px` $\rightarrow$ sous-blocs et lignes de liste à `12px` $\rightarrow$ champs de saisie à `10px` (et `99px` pour les pilules d'action).
- **Calibrage Desktop des collections** : `ListView` des balances ou transferts à `itemExtent: 58` (`spacing: 6`) ; `SuperTable` multi-devises à `headerRowHeight: 38`, `rowHeight: 40`, montants source et cible alignés à `"end"`.

## 6. Depth & Elevation
- **Franchise sans ombre** : `"designSystem": "material"` avec `elevation: 0` sur les cartes. Le contraste net entre le canevas `#F2F5F7`, le blanc `#FFFFFF` et la bordure `#DCE0DF` suffit à découper chaque bloc avec clarté.
- **Zéro effet vitreux** : n'utilisez jamais `liquidGlass`, `neumorphism` ni d'ombres diffuses colorées.

## 7. Do's and Don'ts
- **Do** : Toujours apparier `#9FE870` avec l'encre vert forêt `#163300` (jamais de texte blanc `#FFFFFF` sur `#9FE870`).
- **Do** : Afficher distinctement la devise, le taux appliqué et les frais dans des `SuperValue` atomiques séparés (`label` + `binding`).
- **Do** : Aligner à droite tous les montants, frais et équivalents convertis (`textAlign: "end"`).
- **Do** : Fournir un `emptyText` explicite en français (`"Aucun transfert international pour cette devise"`).
- **Don't** : Ne jamais écrire en blanc sur un bouton ou badge `#9FE870` (illisible et hors norme WCAG).
- **Don't** : Ne jamais utiliser `#9FE870` comme couleur de fond d'écran ou de grande carte entière.
- **Don't** : Ne jamais donner aux éléments enfants un rayon supérieur au `16px` de leur carte parente (hors boutons pilules).
- **Don't** : Ne jamais regrouper le détail des frais de change dans un bloc `textarea` libre.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Balances devises / Historique & Coordonnées bancaires)** : `mainLayout` avec `west: true`, `westSize: 320`, `resizeSides: true`, `"autoSides": []` ; le volet `center` affiche les coordonnées locales IBAN/ACH et les opérations de la devise sélectionnée.
- **Bandeau de balances (`north`)** : 3 à 4 cartes de devises principales (`EUR`, `USD`, `GBP`, `CHF`) disposées en `row` (`northSize: 116`, `spacing: 16`).
- **Simulateur d'envoi / Bénéficiaire** : bornez la carte centrale à `maxWidth: "680px"` (`crossAxisAlignment: "center"`) et gardez `"autoSides": []` sur tout layout ayant `scrollable: true`.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour activer le design system Wise :

```json
{
  "mode": "light",
  "accent": "#163300",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#F2F5F7",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 16,
      "borderWidth": 1,
      "borderColor": "#DCE0DF",
      "elevation": 0,
      "padding": 20
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 12,
      "padding": 12,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#E8F7DC",
            "borderColor": "#163300",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "amount-eur": {
      "type": "value",
      "label": "Balance EUR",
      "text": "8 420,00 EUR",
      "fontFamily": "Inter",
      "fontSize": 26,
      "fontWeight": "bold",
      "color": "#0E0F0C"
    },
    "iban-code": {
      "type": "value",
      "label": "IBAN / SWIFT",
      "text": "BE68 9670 1234 5678 · TRWIBEB1",
      "fontFamily": "Consolas",
      "fontSize": 12,
      "color": "#454745"
    }
  }
}
```
