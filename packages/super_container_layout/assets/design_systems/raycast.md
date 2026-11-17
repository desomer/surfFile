---
name: "Raycast"
slug: "raycast"
category: "developer-tools"
tagline: "Verre liquide sombre translucide, contours lumineux #383A46 et accent corail #FF6363"
description: "Esthétique de lanceur de commandes Desktop haute vitesse exploitant le système liquidGlass sur des surfaces sombres translucides #18191F, réhaussées d'arêtes spéculaires #383A46 et d'un corail vif #FF6363. Idéal pour les palettes d'actions, hubs d'extensions, lanceurs rapides, gestionnaires de snippets et utilitaires système."
mode: "dark"
accent: "#FF6363"
canvasColor: "#0D0E11"
surfaceColor: "#18191F"
textColor: "#F5F5F7"
mutedTextColor: "#9A9AA1"
borderColor: "#2E3039"
cardRadius: 14
surfaceSystem: "liquidGlass"
fontFamily: "Inter"
---

# Raycast — DESIGN.md

## 1. Visual Theme & Atmosphere
Cette esthétique capture l'**élégance tactile d'un lanceur de commandes natif en verre fumé** : aérien, instantané, centré sur le clavier et subtilement spéculaire. Sur un fond nuit profond (`#0D0E11`, subtilement animé d'un dégradé radial sombre pour nourrir la réfraction), les panneaux principaux adoptent `designSystem: "liquidGlass"` avec un flou d'arrière-plan soyeux (`backdropBlur: 24`), un voile ardoise translucide (`#CC18191F`) et un liseré lumineux `1px` (`#383A46`). L'accent corail vibrant (`#FF6363`) dynamise les actions clés et indicateurs d'extensions.

*Note : Ce guide constitue une analyse et une interprétation indépendante de tokens de design inspirés par les lanceurs de productivité Desktop en verre sombre, formulée spécifiquement pour `super_container_layout`.*

## 2. Color Palette & Roles

| Rôle sémantique | Code Hex | Application dans `super_container_layout` |
| :--- | :--- | :--- |
| **Canvas / Background** | `#0D0E11` | `styles["background"].color` (ou dégradé `#0D0E11` $\rightarrow$ `#171421`, `padding: 0`) |
| **Primary Glass Surface** | `#18191F` | Surface de référence (`fill` translucide `#CC18191F` en `liquidGlass`) |
| **Specular Glass Rim** | `#383A46` | `borderColor` (`borderWidth: 1`) des panneaux `liquidGlass` principaux |
| **Internal Hairline / Divider** | `#2E3039` | `SuperSeparator.lineColor` et bordures internes discrètes |
| **Primary Text** | `#F5F5F7` | `SuperValue.color` explicite obligatoire (titres, commandes, résultats) |
| **Muted / Secondary Text** | `#9A9AA1` | `SuperValue.color` explicite (catégories d'extension, raccourcis `Ctrl+K`) |
| **Brand Accent + On-Accent** | `#FF6363` / `#0D0E11` | Racine `"accent"`, `SuperAction` primaire (`color: "#0D0E11"` pour contraste AA 6.7:1) |
| **Selected Row State** | `#262833` | `styles["<listId>:item"].states.selected.style.color` (bordure `#FF6363`) |
| **Semantic Success** | `#30D158` | `SuperIndicator` actif / connecté (fond `#132B1B`, texte `#5CE07B`) |
| **Semantic Warning** | `#FFD60A` | `SuperIndicator` mise à jour / latence (fond `#2B250C`, texte `#FFE047`) |
| **Semantic Error** | `#FF453A` | `SuperIndicator` échec script / déconnecté (fond `#2E1416`, texte `#FF7970`) |

## 3. Typography Rules
- **Familles Desktop recommandées** : **`"Inter"`** pour les titres de lanceur, les lignes de commandes et les panneaux d'aperçu ; **`"Cascadia Mono"`** pour les touches de raccourcis clavier (`Alt+Space`, `Ctrl+K`), alias de commandes et paramètres CLI.
- **Règle critique `liquidGlass`** : contrairement au mode `material` uni, `liquidGlass` n'inverse pas automatiquement la couleur du texte interne ; déclare **toujours explicitement** `"color": "#F5F5F7"` ou `"#9A9AA1"` sur chaque `SuperValue`.

| Niveau (`SuperValue`) | `fontFamily` | `fontSize` | `fontWeight` | `color` | `letterSpacing` | Usage typique |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Command Header / KPI** | `"Inter"` | `22` | `"semibold"` | `#F5F5F7` | `-0.3` | Barre de recherche maîtresse ou métrique phare |
| **2. Section / Pane Title** | `"Inter"` | `15` | `"semibold"` | `#F5F5F7` | `-0.1` | Titre d'aperçu détail ou groupe de commandes |
| **3. Command Row Title** | `"Inter"` | `14` | `"medium"` | `#F5F5F7` | `0.0` | Intitulé de commande, snippet ou script |
| **4. Shortcut / Subtitle** | `"Cascadia Mono"` | `12` | `"normal"` | `#9A9AA1` | `0.2` | Raccourci keycap (`Alt+Space`, `Ctrl+K`) ou alias CLI |

## 4. Component Stylings
- **Panneaux Verre Liquide (`Card`)** : `designSystem: "liquidGlass"`, `fill: { "type": "linear", "start": "#D91E2028", "end": "#B814151B", "angle": 135 }`, `backdropBlur: 24`, `radius: 14`, `borderWidth: 1`, `borderColor: "#383A46"`, `padding: 16`.
- **Boutons (`SuperAction`)** :
  - *Primaire corail* : `variant: "filled"`, `kind: "textAndIcon"`, `fontFamily: "Inter"`, `backgroundColor: "#FF6363"`, `color: "#0D0E11"`, `iconColor: "#0D0E11"`, `radius: 8`, `fontSize: 13`, `fontWeight: "semibold"`, `horizontalPadding: 14`, `verticalPadding: 8` (utiliser une encre sombre `#0D0E11` sur `#FF6363` garantit le contraste AA ; si un texte `#FFFFFF` est requis, assombrir le fond en `#D9383A`).
  - *Secondaire translucide* : `variant: "outlined"`, `fontFamily: "Inter"`, `backgroundColor: "#22242E"`, `borderColor: "#383A46"`, `borderWidth: 1`, `color: "#F5F5F7"`, `iconColor: "#9A9AA1"`, `radius: 8`.
  - *Icône / Action barre inférieure* : `variant: "icon"`, `iconColor: "#9A9AA1"`, `tooltip` systématique.
- **Barre de recherche & Saisie (`SuperValue` en `mode: "input"`)** : `fontFamily: "Inter"`, `field.fillColor: "#131419"`, `field.borderColor: "#383A46"`, `field.radius: 10`, `color: "#F5F5F7"`, placeholder concis (`"Rechercher une commande, un script ou un outil..."`).
- **Lignes de commandes (`<listId>:item`)** : `designSystem: "liquidGlass"`, `color: "#00000000"`, `radius: 10`, `paddingInsets: [8, 12, 8, 12]`, `hoverEffect: true`, `hoverTint: "custom"`, `hoverColor: "#20222B"` (intitulés en `fontFamily: "Inter"`). `states.selected` applique un fond `#262833` et un contour `1px` `#FF6363`.
- **Badges raccourcis / Keycaps (`SuperIndicator`)** : `fontFamily: "Cascadia Mono"`, `fontSize: 11`, `fontWeight: "medium"`, `backgroundColor: "#232530"`, `borderColor: "#383A46"`, `borderWidth: 1`, `color: "#D1D1D6"`, `iconColor: "#FF6363"`, `radius: 6`, `horizontalPadding: 7`, `verticalPadding: 3` (ex. `"Alt+Space"`, `"Ctrl+K"`).

## 5. Layout Principles
- **Échelle d'espacement** : `4, 8, 12, 16, 20, 24`. `styles["background"].padding: 0` ; `zoneFlows.*.padding: 16`, `spacing: 12` pour laisser respirer les reflets vitrés entre panneaux.
- **Rayons concentriques fluides** : Panneau principal `radius: 14` $\rightarrow$ Champ de recherche / Ligne `radius: 10` $\rightarrow$ Bouton `radius: 8` $\rightarrow$ Keycap `radius: 6`.
- **Calibrage des listes** : `ListView` ultra-nette avec `itemExtent: 46` (icône + commande + catégorie à gauche, badge raccourci à droite en zone `east`), `spacing: 4`.

## 6. Depth & Elevation
- **Unité `liquidGlass` stricte** : utiliser `designSystem: "liquidGlass"` de façon cohérente sur l'ensemble de l'écran (ne jamais hybrider `neumorphism` et `liquidGlass`).
- **Profondeur optique** : associer un fond `styles["background"]` légèrement nuancé (`#0D0E11` vers `#181320`) afin que `backdropBlur: 24` révèle une vraie translucidité, soutenue par une ombre profonde douce (`shadow: { "enabled": true, "color": "#000000", "opacity": 0.45, "blur": 28, "spread": -4, "dx": 0, "dy": 12 }`).

## 7. Do's and Don'ts
- **Do** : Déclarer explicitement `color: "#F5F5F7"` et `"#9A9AA1"` sur tous les textes posés sur une surface `liquidGlass`.
- **Do** : Structurer les vues autour d'un champ de recherche/filtre proéminent en `north` et d'un split Liste + Aperçu en `center`.
- **Do** : Utiliser des `SuperIndicator` style touches clavier (`#232530`, bordure `#383A46`) alignés à droite des lignes.
- **Do** : Maintenir un contour spéculaire fin `1px` `#383A46` sur chaque carte vitrée.
- **Don't** : Ne jamais poser du texte blanc `#FFFFFF` en corps `12`–`13px` sur un bouton plein `#FF6363` (préférer `#0D0E11`).
- **Don't** : Ne jamais mélanger `liquidGlass` et `material` opaque disparate dans une même grille.
- **Don't** : Ne jamais surcharger une ligne de commande avec plus de 3 informations textuelles.
- **Don't** : Ne jamais oublier `"named": {}` dans les objets `states`.

## 8. Responsive & Desktop Ergonomics
- **Architecture Command Palette / Hub (`mainLayout`)** : barre de filtre rapide en `north` (`autoSides: ["north"]`), liste maîtresse de commandes en `west` (`westSize: 340`, `resizeSides: true`, `"autoSides": []`) et panneau d'aperçu riche / métadonnées `[?]` en `center` (`expandSlots: true`), complété optionnellement d'une barre d'actions `south` compacte (`southSize: 44`).

## 9. Agent Prompt Guide (super_container_layout)

```json
{
  "mode": "dark",
  "accent": "#FF6363",
  "styles": {
    "background": {
      "designSystem": "liquidGlass",
      "color": "#0D0E11",
      "fill": {
        "type": "linear",
        "start": "#0D0E11",
        "end": "#171421",
        "angle": 135
      },
      "padding": 0
    },
    "card-main": {
      "designSystem": "liquidGlass",
      "color": "#18191F",
      "fill": {
        "type": "linear",
        "start": "#D91E2028",
        "end": "#B814151B",
        "angle": 135
      },
      "backdropBlur": 24,
      "radius": 14,
      "borderWidth": 1,
      "borderColor": "#383A46",
      "padding": 16,
      "shadow": {
        "enabled": true,
        "color": "#000000",
        "opacity": 0.45,
        "blur": 28,
        "spread": -4,
        "dx": 0,
        "dy": 12
      }
    },
    "list-items:item": {
      "designSystem": "liquidGlass",
      "color": "#00000000",
      "radius": 10,
      "paddingInsets": [8, 12, 8, 12],
      "hoverEffect": true,
      "hoverTint": "custom",
      "hoverColor": "#20222B",
      "states": {
        "named": {},
        "selected": {
          "style": {
            "color": "#262833",
            "borderWidth": 1,
            "borderColor": "#FF6363"
          },
          "properties": ["background", "border"]
        }
      }
    }
  },
  "components": {
    "cmd-header": {
      "type": "value",
      "text": "Palette de commandes",
      "fontFamily": "Inter",
      "fontSize": 22,
      "fontWeight": "semibold",
      "letterSpacing": -0.3,
      "color": "#F5F5F7"
    },
    "keycap-shortcut": {
      "type": "indicator",
      "icon": "bolt",
      "label": "Ctrl+K",
      "fontFamily": "Cascadia Mono",
      "fontSize": 11,
      "fontWeight": "medium",
      "color": "#D1D1D6",
      "iconColor": "#FF6363",
      "backgroundColor": "#232530",
      "borderColor": "#383A46",
      "borderWidth": 1,
      "radius": 6,
      "horizontalPadding": 7,
      "verticalPadding": 3
    }
  }
}
```
