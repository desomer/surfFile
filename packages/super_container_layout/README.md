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

`SuperApp` prend en charge la restauration et la sauvegarde de l'apparence, le
reset des dispositions, la mise à jour de la transparence de fenêtre ainsi
qu'une coquille `MaterialApp` avec le mode d'édition et le fond stylé :

```dart
const SuperApp(home: MyHomePage(), title: 'Mon application')
```

Un `AppearanceStore` personnalisé peut être fourni via `appearanceStore`.
