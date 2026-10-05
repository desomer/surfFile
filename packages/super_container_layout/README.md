# super_container_layout

Package Flutter autonome regroupant `SuperContainer`, `SuperLayout`, leurs
éditeurs, leurs styles et le modèle de persistance associé.

Ajoutez le package à `pubspec.yaml` :

```yaml
dependencies:
  super_container_layout:
    path: packages/super_container_layout
```

Puis importez son point d’entrée :

```dart
import 'package:super_container_layout/super_container_layout.dart';
```

`SuperLayout` organise des `SlotImplementation` dans les neuf zones de
`SuperLayoutConfig`. `SuperContainer` fournit l’édition contextuelle des styles
et peut partager les styles via `AppearanceScope` et `AppearanceSlot`.

`AppearanceSlot` est une classe extensible. Les constantes existantes
(`AppearanceSlot.sidebar`, etc.) et `AppearanceSlot.values` restent disponibles.
Un slot personnalisé fournit ses fonctions de lecture, écriture et remise à
zéro dans `Appearance` :

```dart
final customSlot = AppearanceSlot(
  'Mon panneau',
  name: 'custom-panel',
  read: (appearance) => appearance.sidebarStyle,
  write: (appearance, style) => appearance.copyWith(sidebarStyle: style),
  reset: (appearance) =>
      appearance.copyWith(sidebarStyle: const ContainerStyle()),
);
SuperContainer(slot: customSlot, child: const Text('Mon panneau'));
```

Cet exemple partage le style du panneau gauche. La persistance dépend des
champs d'`Appearance` utilisés ; créer un slot ne crée pas de nouveau champ de
stockage. Les propriétés `selectedVariant` et `standard` permettent de lier
une paire de variantes. `values` contient uniquement les slots prédéfinis.

En mode édition, les zones vides de `SuperLayout` affichent un bouton « + »
pour choisir un slot visible parmi ceux fournis à `slots`. Un slot déjà placé
est déplacé, sans duplication. Le placement passe par `onChanged`, comme le
glisser-déposer. Ces boutons sont masqués si `editable` ou `showZoneNames` est
désactivé, et suivent la sélection du parent pour les dispositions imbriquées.

Si le `SuperApp` possède un `registry`, le sélecteur propose aussi ses composants
sous le nom `Registre : <clé>`. Ils deviennent des slots déplaçables du layout,
identifiés par `registry:<clé encodée comme composant URI>` (préfixe répété si
un slot fourni utilise déjà cet identifiant). Ces identifiants sont enregistrés dans `placements` via
`onChanged` ; conserver les mêmes clés de registre et identifiants de slots
permet de restaurer la disposition. Choisir à nouveau un composant le déplace,
sans le dupliquer dans ce layout.

```dart
final registry = Registry();
registry.registry['horloge'] = const Text('Horloge');
SuperApp(registry: registry, home: const SuperLayout());
```

`SuperApp` prend en charge la restauration et la sauvegarde de l'apparence, le
reset des dispositions, la mise à jour de la transparence de fenêtre ainsi
qu'une coquille `MaterialApp` avec le mode d'édition et le fond stylé :

```dart
const SuperApp(home: MyHomePage(), title: 'Mon application')
```

Un `AppearanceStore` personnalisé peut être fourni via `appearanceStore`.

Depuis le `BuildContext` d'un descendant (y compris dans un `SuperLayout`, un
`SuperContainer` ou un dialogue), `SuperApp.of(context)` retourne le `SuperApp`
le plus proche, donnant accès notamment à `title` et `registry`.
`SuperApp.maybeOf(context)` retourne `null` en l'absence d'application ;
`of` lève une `FlutterError` dans ce cas. La recherche utilise
`dependOnInheritedWidgetOfExactType` et reconstruit les widgets dépendants
lorsque la configuration du `SuperApp` est remplacée.

```dart
Builder(
  builder: (context) {
    final app = SuperApp.of(context);
    return Text(app.title);
  },
)
```
