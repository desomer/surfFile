---
name: "Ollama"
slug: "ollama"
category: "ai-platforms"
tagline: "Monochrome minimaliste d'une netteté chirurgicale pensé pour l'IA locale et les outils développeur."
description: "Système visuel achromatique ultra-épuré combinant un canevas blanc pur (#FFFFFF), des surfaces gris perle (#F9F9F9), une typographie Inter minimaliste, des boutons encre noire (#171717) et des métriques techniques en chasse fixe JetBrains Mono. Idéal pour les gestionnaires de modèles locaux, registres techniques, runners CLI graphiques et utilitaires Desktop sobres."
mode: "light"
accent: "#171717"
canvasColor: "#FFFFFF"
surfaceColor: "#F9F9F9"
textColor: "#111111"
mutedTextColor: "#737373"
borderColor: "#E5E5E5"
cardRadius: 12
surfaceSystem: "material"
fontFamily: "Inter"
---

# Ollama — DESIGN.md

> *Note : Analyse indépendante de design system formulée comme source d'inspiration visuelle originale et adaptée au moteur GenUI `super_container_layout`.*

## 1. Visual Theme & Atmosphere
L'esthétique repose sur un dépouillement utilitaire radical : zéro dégradé décoratif, zéro teinte superflue, zéro ombre théâtrale. Sur un canevas blanc franc `#FFFFFF`, l'architecture s'exprime uniquement par le contraste typographique `"Inter"` encre `#111111`, des conteneurs gris nuage `#F9F9F9` et des filets `#E5E5E5` d'une précision millimétrique. L'identité d'outil d'infrastructure IA locale se manifeste dans l'usage ciblé de la police `"JetBrains Mono"` (ou `"Consolas"`) pour les balises de quantification (`Q4_K_M`), tailles de paramètres (`8B`, `70B`), empreintes SHA et commandes CLI d'exécution.

## 2. Color Palette & Roles

| Rôle sémantique | Hex | Usage dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas blanc pur** | `#FFFFFF` | `styles["background"].color` — fond principal dégagé (`padding: 0`) |
| **Surface douce** | `#F9F9F9` | Cartes secondaires, panneaux de filtres, conteneurs de paramètres |
| **Surface de contrôle** | `#F3F3F3` | Fond de pastilles techniques, `tabBarStyle` et lignes survolées |
| **Bordure neutre** | `#E5E5E5` | Filet `1px` structurant cartes, tableaux et champs de recherche |
| **Encre primaire** | `#111111` | Titres, noms de modèles et valeurs principales |
| **Texte secondaire** | `#737373` | Descriptions courtes, tailles disque, horodatages et légendes |
| **Accent Encre Noire** | `#171717` | Racine `"accent"`, boutons d'action primaires et bordure de focus |
| **Sélection active** | `#EFEFEF` | Fond `states.selected` sur les listes avec filet `#171717` |
| **Statut Prêt / En cours** | `#15803D` | Indicateur discret de modèle chargé sur pastille `#DCFCE7` |
| **Statut Erreur / Arrêt** | `#DC2626` | Action de suppression ou erreur d'exécution sur fond `#FEE2E2` |

## 3. Typography Rules
Utilisez **`"Inter"`** pour l'interface minimaliste, la structure de navigation et les descriptions, et **`"JetBrains Mono"`** (ou **`"Consolas"`**) pour les balises de modèles (`Q4_K_M`, `8B`, `70B`), empreintes SHA, commandes CLI (`ollama run ...`), ports réseau et tailles mémoire.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | Usage recommandé |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Titre d'écran / Compteur clé** | `"Inter"` | `24` | `"bold"` | `"#111111"` | Titre de catalogue ou métrique principale du nœud local |
| **2. Titre de carte / Modèle** | `"Inter"` | `16` | `"semibold"` | `"#111111"` | En-tête de `Card` ou nom d'une famille de modèles |
| **3. Corps / Champ / Cellule** | `"Inter"` | `13` | `"normal"` / `"medium"` | `"#111111"` | Paramètres de configuration, champs `input` et cellules |
| **4. Tag technique / Métadonnée** | `"JetBrains Mono"` | `12` | `"normal"` | `"#737373"` | Tags `Q4_K_M`, `8B`, `70B`, SHA, commandes CLI et `tok/s` |

## 4. Component Stylings
- **Cartes (`Card`)** : `designSystem: "material"`, `color: "#F9F9F9"` (ou `"#FFFFFF"` sur zone contrastée), `radius: 12`, `borderWidth: 1`, `borderColor: "#E5E5E5"`, `elevation: 0`, `padding: 16`.
- **Boutons (`SuperAction`)** :
  - Primaire (`variant: "filled"`) : `fontFamily: "Inter"`, `fontWeight: "semibold"`, `backgroundColor: "#171717"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 99` (pilule franche) ou `8`, `horizontalPadding: 18`, `verticalPadding: 10` (contraste maximal AAA > 17:1).
  - Secondaire (`variant: "outlined"`) : `fontFamily: "Inter"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#E5E5E5"`, `borderWidth: 1`, `color: "#111111"`, `iconColor: "#111111"`, `radius: 8`.
  - Icône d'outil (`variant: "icon"`) : `iconColor: "#737373"` avec `tooltip` obligatoire (ex. `"Copier la commande"`).
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : recherche et paramètres épurés en `fontFamily: "Inter"` (ou `"JetBrains Mono"` pour les commandes CLI et endpoints) sur fond `"#FFFFFF"`, bordure `1px` `"#E5E5E5"`, `radius: 8`, `placeholder` concis (ex. `"Rechercher un modèle (ex: qwen2.5-coder)"`).
- **Collections (`ListView` / `Table`)** : `styles["<listId>:item"]` avec `color: "#FFFFFF"`, `radius: 8`, `padding: 12`, `hoverEffect: true`, et `states.selected` en `color: "#F3F3F3"`, `borderColor: "#171717"`, `borderWidth: 1`.
- **Pastilles (`SuperIndicator`)** : badges de quantification et de paramètres (`Q4_K_M`, `8B`, `70B`) en `fontFamily: "JetBrains Mono"`, `radius: 6` ou `99`, `horizontalPadding: 8`, `verticalPadding: 4`, `backgroundColor: "#F3F3F3"`, `borderColor: "#E5E5E5"`, `borderWidth: 1`, `color: "#111111"`, `iconColor: "#171717"`.

## 5. Layout Principles
- **Échelle d'espacement** : respectez strictement `4, 8, 12, 16, 20, 24`. Gardez `styles["background"].padding` à `0`, `zoneFlows.*.padding` à `16`, et `spacing` à `12` entre cartes sœurs (`padding >= spacing`).
- **Rayons concentriques** : `Card` parente à `12px` $\rightarrow$ barres segmentées à `10px` $\rightarrow$ lignes, entrées et badges carrés à `8px` (ou `99px` réservé aux boutons pilules autonomes).
- **Calibrage Desktop des collections** : `ListView` de bibliothèque à `itemExtent: 56` (`spacing: 4`) ; `SuperTable` des modèles installés à `headerRowHeight: 36`, `rowHeight: 38`, colonne nom en `fillPercent: 100` et colonnes taille/VRAM alignées à `"end"` (`110px`).

## 6. Depth & Elevation
- **Zéro ornementation artificielle** : `"designSystem": "material"` exclusif avec `elevation: 0` sur l'ensemble des panneaux.
- **Séparation par trait fin** : la hiérarchie spatiale repose intégralement sur l'alternance `#FFFFFF` / `#F9F9F9` et la netteté des bordures `1px` `#E5E5E5` (passant à `#171717` uniquement sur l'élément sélectionné ou focalisé).

## 7. Do's and Don'ts
- **Do** : Afficher les balises (`Q4_K_M`, `8B`, `70B`), empreintes SHA, poids en Go, débits `tok/s` et ports HTTP en `"JetBrains Mono"` (ou `"Consolas"`) alignés à droite dans les listes et tableaux.
- **Do** : Conserver une palette strictement monochrome à 95 %, ne laissant la couleur apparaître que sur un point d'état opérationnel (chargé / erreur).
- **Do** : Privilégier `variant: "segmented"` pour basculer entre 2 à 4 filtres courts (`"Tous"`, `"Installés"`, `"En mémoire"`).
- **Do** : Rédiger des `emptyText` sobres et actionnables (`"Aucun modèle téléchargé sur cette machine"`).
- **Don't** : Ne jamais ajouter d'ombres portées épaisses, de flous `liquidGlass` ni d'effets `neon`.
- **Don't** : Ne jamais introduire de bleu ou de violet générique sur les boutons secondaires ou les en-têtes.
- **Don't** : Ne jamais concaténer étiquette et valeur dans un même `SuperValue` (`"Taille : 4.7 GB"` est proscrit ; séparez `label` et `text`/`binding`).
- **Don't** : Ne jamais laisser un bouton d'action sans `color: "#FFFFFF"` lorsqu'il utilise le fond `#171717`.

## 8. Responsive & Desktop Ergonomics
- **Maître / Détail (Catalogue de modèles & Inspecteur)** : configurez `mainLayout` avec `west: true`, `westSize: 310`, `resizeSides: true` et `"autoSides": []`. Le volet `west` accueille le champ de filtrage en `north` (`autoSides: ["north"]`) et la `ListView` en `center` (`expandSlots: true`).
- **Bandeau KPI ressources locales** : en `north` (`northSize: 104`), alignez 3 à 4 cartes compactes (`Modèles actifs`, `VRAM utilisée`, `Débit moyen`, `Port API`) en `row` (`spacing: 12`).
- **Formulaires de serveur / Modelfile** : limitez la largeur utile à `maxWidth: "720px"` et gardez `"autoSides": []` sur tout conteneur `scrollable: true`.

## 9. Agent Prompt Guide (super_container_layout)
Extrait JSON prêt à appliquer via `applyVibe` pour déployer le thème monochrome Ollama :

```json
{
  "mode": "light",
  "accent": "#171717",
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#F9F9F9",
      "radius": 12,
      "borderWidth": 1,
      "borderColor": "#E5E5E5",
      "elevation": 0,
      "padding": 16
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "radius": 8,
      "borderWidth": 1,
      "borderColor": "#E5E5E5",
      "padding": 12,
      "hoverEffect": true,
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#F3F3F3",
            "borderColor": "#171717",
            "borderWidth": 1
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "title-catalog": {
      "type": "value",
      "text": "Modèles locaux",
      "fontFamily": "Inter",
      "fontSize": 24,
      "fontWeight": "bold",
      "color": "#111111"
    },
    "badge-quant": {
      "type": "indicator",
      "icon": "terminal",
      "label": "70B · Q4_K_M",
      "fontFamily": "JetBrains Mono",
      "fontSize": 11,
      "color": "#111111",
      "iconColor": "#171717",
      "backgroundColor": "#F3F3F3",
      "borderColor": "#E5E5E5",
      "borderWidth": 1,
      "radius": 6,
      "horizontalPadding": 8,
      "verticalPadding": 4
    }
  }
}
```
