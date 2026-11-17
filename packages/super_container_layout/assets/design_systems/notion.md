---
name: "Notion"
slug: "notion"
category: "productivity-saas"
tagline: "Atelier papier chaleureux, pierre douce et encre fusain apaisée"
description: "Système visuel clair et éditorial associant un canevas blanc pur #FFFFFF à des surfaces latérales pierre chaude #F7F6F3, une encre charbon doux #37352F et des titres sérif optionnels. Parfait pour les bases de connaissances, wikis d'équipe, notes structurées, CRM légers et portails documentaires."
mode: "light"
accent: "#2383E2"
canvasColor: "#FFFFFF"
surfaceColor: "#F7F6F3"
textColor: "#37352F"
mutedTextColor: "#787774"
borderColor: "#E9E9E7"
cardRadius: 8
surfaceSystem: "material"
fontFamily: "Inter"
---

# Notion — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette esthétique évoque une **feuille de papier éditoriale calme et accueillante**, où l'interface s'efface au profit de l'écriture, de la lecture et de la structuration des idées. L'absence totale de noir pur `#000000` (remplacé par une encre fusain chaude `#37352F`) et l'alternance subtile entre le blanc lumineux (`#FFFFFF`) et la pierre crayeuse (`#F7F6F3`) éliminent toute dureté clinique. La mise en page reste plate (`elevation: 0`), feutrée et sans friction visuelle.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les espaces de travail documentaires modernes, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#FFFFFF` | `styles["background"].color` (`padding: 0`, espace éditorial principal) |
| **Primary Card Surface** | `#F7F6F3` | `styles["<cardId>"].color` (volets latéraux, encarts callout, blocs propriétés) |
| **Elevated / Secondary Surface** | `#FFFFFF` | Cartes posées sur fond `#F7F6F3` ou sous-conteneurs bordés `#E9E9E7` |
| **Primary Text** | `#37352F` | `SuperValue` titres, paragraphes, cellules principales |
| **Muted / Secondary Text** | `#787774` | `SuperValue` étiquettes de propriétés, dates, légendes discrètes |
| **Hairline / Border** | `#E9E9E7` | `borderColor` (`borderWidth: 1`) et traits `SuperSeparator` |
| **Brand Accent + On-Accent** | `#2383E2` / `#FFFFFF` | Racine `"accent"`, boutons primaires `"filled"` et liens actifs |
| **Selected Row State** | `#EBF3FB` | `styles["<listId>:item"].states.selected.style.color` (bordure `#2383E2`) |
| **Semantic Success** | `#0F7B6C` | `SuperIndicator` validé / publié (fond `#EDF3EC`, texte `#0F7B6C`) |
| **Semantic Warning** | `#D9730D` | `SuperIndicator` brouillon / révision (fond `#FAEBDD`, texte `#D9730D`) |
| **Semantic Error** | `#E03E3E` | `SuperIndicator` urgent / rejeté (fond `#FBE4E4`, texte `#E03E3E`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Georgia"`** sur le grand titre éditorial d'écran (`fontSize: 24`–`26`, `fontWeight: "bold"`) pour un cachet documentaire chaleureux ; **`"Inter"`** (repli `"Segoe UI"`) pour l'espace de travail, les panneaux latéraux et les bases de données tabulaires ; **`"Consolas"`** pour les extraits techniques, formules et clés de propriétés.
- **Hiérarchie douce** : interlignage respirant (`lineHeight: 1.4` sur les textes descriptifs courts) et contrastes mesurés entre `#37352F` et `#787774`.

| Niveau (`SuperValue`) | `fontSize` | `fontWeight` | `color` | Famille conseillée | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Screen Title / KPI** | `24`–`26` | `"bold"` | `#37352F` | `"Georgia"` ou `"Inter"` | Titre éditorial de page wiki, espace projet ou KPI clé |
| **2. Section / Card Title** | `16` | `"semibold"` | `#37352F` | `"Inter"` | Titre d'encart, vue de collection ou panneau |
| **3. Body / Field Value** | `14` | `"normal"` | `#37352F` | `"Inter"` | Valeurs de fiche, entrées de liste, cellules et saisie |
| **4. Label / Code / Metadata** | `12` | `"normal"` | `#787774` | `"Inter"` / `"Consolas"` | Nom d'attribut, auteur (`Inter`), extrait technique (`Consolas`) |

## 4. Component Stylings
- **Cards & Callouts (`Card`)** : `designSystem: "material"`, `color: "#F7F6F3"` (sur canevas `#FFFFFF`) ou `#FFFFFF` avec `borderWidth: 1` et `borderColor: "#E9E9E7"`, `radius: 8`, `elevation: 0`, `padding: 16` ou `20`.
- **Boutons (`SuperAction`)** :
  - *Primaire* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Inter"`, `backgroundColor: "#2383E2"`, `color: "#FFFFFF"`, `iconColor: "#FFFFFF"`, `radius: 6`, `fontSize: 13`, `fontWeight: "medium"`, `horizontalPadding: 12`, `verticalPadding: 8`.
  - *Secondaire* : `variant: "outlined"`, `backgroundColor: "#FFFFFF"`, `borderColor: "#E9E9E7"`, `borderWidth: 1`, `color: "#37352F"`, `iconColor: "#787774"`, `radius: 6`.
  - *Tertiaire / Barre d'outils* : `variant: "text"` ou `variant: "icon"`, `color: "#787774"`, `iconColor: "#787774"` (infobulle `tooltip` systématique).
- **Champs de saisie (`SuperValue` en `mode: "input"`)** : `field.fillColor: "#FFFFFF"`, `field.borderColor: "#E0DFDC"`, `field.radius: 6`, `color: "#37352F"`, labels sobres non redondants.
- **Collections (`<listId>:item` & `Table`)** : lignes au repos transparentes (`"#00000000"`), `radius: 6`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#EFEFED"`. Sélection active `states.selected` en bleu aquarelle `#EBF3FB` avec filet `1px` `#2383E2`.
- **Tags pastel (`SuperIndicator`)** : `radius: 6` (plutôt que pilule ronde excessive), `fontSize: 12`, `fontWeight: "medium"`, `horizontalPadding: 8`, `verticalPadding: 3`, `borderWidth: 0`, teintes pastel chaudes (sauge `#EDF3EC`, ambre `#FAEBDD`, lavande `#EAE4F2` avec texte `#6940A5`).

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24, 32`. `styles["background"].padding: 0`. Générosité éditoriale dans la zone centrale (`padding: 20` ou `24`, `spacing: 12` ou `16`).
- **Rayons concentriques sobres** : Cartes et encarts `radius: 8` $\rightarrow$ Lignes, champs, tags et boutons `radius: 6`.
- **Densité des collections** : `ListView` d'arborescence ou de pages avec `itemExtent: 40` à `48`, `spacing: 4`. `SuperTable` type base documentaire avec `headerRowHeight: 36` et `rowHeight: 38`.

## 6. Depth & Elevation
- **Aplat papier intégral** : `designSystem: "material"` et `elevation: 0` partout sur la grille principale.
- **Séparation chromatique chaude** : le volet de navigation (`#F7F6F3`) se distingue naturellement de la page centrale (`#FFFFFF`) via un simple filet vertical `1px` `#E9E9E7`, sans aucune ombre portée.
- **Menus et popovers uniquement** : ombre légère ultra-diffuse (`opacity: 0.08`, `blur: 16`, `dy: 4`) réservée aux surfaces flottantes contextuelles.

## 7. Do's and Don'ts
- **Do** : Utiliser systématiquement `#37352F` pour le texte principal et `#787774` pour les métadonnées afin de préserver la chaleur papier.
- **Do** : Privilégier des tags `SuperIndicator` aux tons pastel feutrés (`radius: 6`) pour catégoriser statuts et domaines.
- **Do** : Exploiter un `SuperValue` unique (`label` + `binding`) pour les grilles de propriétés de document.
- **Do** : Borner la largeur utile des fiches de lecture et formulaires centraux (`720px`–`780px`) pour le confort oculaire.
- **Don't** : Ne jamais utiliser de gris bleutés froids (`#CBD5E1`) ni de noir `#000000` agressif.
- **Don't** : Ne jamais ajouter d'élévation Material (`elevation: 3`+) ou d'effets `liquidGlass` / `neon`.
- **Don't** : Ne jamais imbriquer trois niveaux de cartes `#F7F6F3` les unes dans les autres.
- **Don't** : Ne jamais créer un champ `textarea` fourre-tout pour remplacer une vraie liste d'attributs atomiques.

## 8. Responsive & Desktop Ergonomics
- **Architecture Sidebar + Page (`mainLayout`)** : volet `west` en pierre `#F7F6F3` (`westSize: 260` à `300`, `resizeSides: true`, `"autoSides": []`) abritant la recherche et la `TreeView` / `ListView` des pages ; zone `center` `#FFFFFF` spacieuse (`expandSlots: true`).
- **En-tête de document / KPI** : zone `north` épurée (`autoSides: ["north"]`) présentant le titre éditorial, 2 ou 3 compteurs synthétiques et le bouton primaire `"Nouveau"` aligné à droite.
- **Discipline du défilement** : sur une fiche documentaire défilante (`scrollable: true`), verrouiller `"autoSides": []` et `maxWidth: "760px"`.

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "light",
  "accent": "#2383E2",
  "components": {
    "doc-title": {
      "type": "value",
      "text": "Base de connaissances Produit",
      "fontFamily": "Georgia",
      "fontSize": 26,
      "fontWeight": "bold",
      "color": "#37352F"
    },
    "doc-owner": {
      "type": "value",
      "label": "Responsable",
      "binding": "pages[?].auteur",
      "fontFamily": "Inter",
      "fontSize": 14,
      "color": "#37352F"
    }
  },
  "styles": {
    "background": {
      "designSystem": "material",
      "color": "#FFFFFF",
      "padding": 0
    },
    "card-main": {
      "designSystem": "material",
      "color": "#F7F6F3",
      "radius": 8,
      "borderWidth": 1,
      "borderColor": "#E9E9E7",
      "elevation": 0,
      "padding": 20
    },
    "list-items:item": {
      "designSystem": "material",
      "color": "#00000000",
      "radius": 6,
      "paddingInsets": [6, 10, 6, 10],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#EFEFED",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#EBF3FB",
            "borderWidth": 1,
            "borderColor": "#2383E2"
          },
          "properties": ["background", "border"]
        }
      }
    }
  }
}
```
