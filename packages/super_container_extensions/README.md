# super_container_extensions

Package d'extensions de composants modulaires pour le moteur [`super_container_layout`](../super_container_layout).

## Composants inclus

- **`SuperCode`** (`type: 'code'`, cle de registre `'Code'`) :
  - Editeur avec coloration YAML ou JavaScript (sans execution).
  - Liaison bidirectionnelle a une chaine de texte d'un repository JSON,
    avec heritage, jokers `[?]` et selection maitre / detail.
  - Sauvegarde automatique temporisee, detection des conflits et lecture seule.
  - Assistant d'ajout et dialogue de configuration du langage et de la liaison.
  - Sans liaison ou sans ligne selectionnee, le champ reste vide et non modifiable.
  - Au-dela de 50 000 caracteres, edition en texte simple sans coloration,
    avec avertissement visible, pour eviter le blocage des gros documents.

- **`SuperChart`** (`type: 'chart'`, clé de registre `'Chart'`) :
  - Graphiques interactifs basés sur `fl_chart` (`LineChart`, `BarChart`, `PieChart`, `ScatterChart`, `RadarChart`).
  - Liaison réactive aux tableaux des repositories JSON (`JsonTextBinding`) avec support des jokers `[?]` (`JsonListScope`).
  - Synchronisation bidirectionnelle de la sélection Maître / Détail (`JsonArrayBinding`).
  - Éditeur visuel complet (`showSuperChartEditor`) et assistant d'ajout (`ChartAddForm` / `chartAddConfigurator`).

## Utilisation

`SuperCode` et `SuperChart` heritent de `SuperStatefulComponent<C>` du moteur.
Ils partagent le contrat `SuperComponent<C>` (`id`, `config`, `behaviours`).
Une liste `behaviours: [...]` declare les comportements en code et remplace
ceux de l'apparence pour l'instance ; `null` conserve l'apparence et `[]`
desactive les comportements, sans modifier les preferences sauvegardees.

```dart
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_container_extensions/super_container_extensions.dart';

final registry = Registry()
  ..bootstrap()
  ..registerAllExtensions();
```

Exemple de configuration dans `Appearance.components` :

```json
{
  "script-editor": {
    "type": "code",
    "mode": "javascript",
    "binding": {
      "repositoryId": "0123456789abcdef0123456789abcdef",
      "path": "scripts[?].source"
    },
    "readOnly": false
  }
}
```

Le placement utilise `registry:Code` (alias `Code`, `SuperCode`, `superCode`).
Le mode par defaut est `yaml`. Le texte reste dans le repository, jamais dans
les preferences d'apparence ni dans l'historique de configuration.

`SuperApp` fournit les localisations Flutter requises par les menus de selection
de l'editeur, en plus de celles de `material_ui`. Avec un `MaterialApp`
`material_ui` autonome, ajouter aussi les delegates de
`package:flutter_localizations/flutter_localizations.dart`
(`GlobalMaterialLocalizations.delegates`, avec un alias d'import pour eviter
le conflit de noms) aux `localizationsDelegates` de l'application.
