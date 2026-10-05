# super_container_layout

`TypedAppearanceScope<T extends Appearance>` raccorde un contrôleur typé aux
widgets génériques du package, avec son codec :

```dart
TypedAppearanceScope<DefaultAppearance>(
  controller: controller,
  codec: const DefaultAppearanceCodec(),
  child: child,
)
```

`TypedAppearanceScope.of<DefaultAppearance>(context)` lit le modèle ;
`controllerOf<DefaultAppearance>(context)` expose le contrôleur typé.
`maybeOf` et `controllerOf` retournent `null` sans scope ; un modèle de type
incompatible produit une `StateError`. Les écritures provenant du contrôleur
générique passent par `codec.prepare`, puis sont vérifiées avant transmission.
Le scope dispose ses adaptateurs, jamais le contrôleur fourni par l'application.
Les scopes de préférences métier restent à composer dans l'application.

`DefaultAppearance` complète `Appearance` avec les dimensions des éléments,
la typographie et le fondu de défilement. Ses maps `styles` et `layouts` ne
contiennent aucun catalogue ou disposition d'application par défaut.
`copyWith`, `withStyle`, `withLayout` et `resetLayouts` conservent les autres
préférences et retournent un `DefaultAppearance`.

Pour sauvegarder ce modèle, fournir explicitement son codec :

```dart
SuperApp(
  appearanceStore: AppearanceStore(codec: const DefaultAppearanceCodec()),
  home: const MyHomePage(),
)
```

Les réglages métier (jauges de disque, transitions de dossiers) et les
catalogues spécifiques restent dans l'application. Une sous-classe peut
ajouter ces données avec un codec dédié ; le codec générique ne les sérialise
pas automatiquement.

Un codec peut aussi composer des préférences indépendantes sans sous-classer
le modèle : `additionalPreferences` expose leur `Listenable`,
`restoreAdditional` applique un document déjà validé et `resetAdditional`
restaure leurs valeurs initiales. `prepare` configure les catalogues/fallbacks
de l'application avant une mise à jour du contrôleur. Le contrôleur persistant
capture le document complet à chaque changement et sérialise les écritures avec
`AppearanceStore.saveEncoded`, y compris pour les préférences indépendantes.
La lecture, les migrations et les imports utilisent le même codec.

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

`AppearanceSlot` est une classe extensible sans catalogue prédéfini.
L'application définit ses slots et fournit leurs fonctions de lecture,
écriture et remise à zéro dans `Appearance` :

```dart
final customSlot = AppearanceSlot(
  'Ma surface',
  name: 'custom-surface',
  read: (appearance) => appearance.style('custom-surface'),
  write: (appearance, style) => appearance.withStyle('custom-surface', style),
  reset: (appearance) => appearance.withStyle('custom-surface', null),
);
SuperContainer(slot: customSlot, child: const Text('Mon panneau'));
```

Cet exemple cree une entree de style persistante sous l'identifiant stable
`custom-surface`. Les propriétés `selectedVariant` et `standard` permettent de lier
une paire de variantes. `selectedVariantResolver` permet une référence différée
pour lier les variantes dans les deux sens.

Le rôle `AppearanceSurfaceRole.applicationBackground` active le rayon nul et
les réglages du fond/de la fenêtre ; le rôle par défaut est `standard`.
L'application définit aussi `editShape` et `extendedLook` selon le rendu.
Le package n'a aucun catalogue ni modele metier d'application. `Appearance`
contient seulement le theme, la fenetre et les maps immuables `styles` et
`layouts`. `background` est l'identifiant du fond de la coquille. Les autres
identifiants sont libres. `withStyle`, `withLayout` et `copyWith` rendent une
nouvelle valeur ; supprimer un style avec `null` restaure le fallback du slot.
`variantStyle(id, standardId, inheritLook: ...)` résout une variante (par exemple
sélectionnée) par identifiants : sans surcharge, la forme est reprise du
style standard, et son aspect aussi si `inheritLook` est vrai ; le néon absent hérite du standard.

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

Le registre accepte aussi des fabriques avec `registerComponent` :

```dart
registry.registerComponent(
  'horloge',
  RegisteredComponent(
    label: 'Horloge',
    sizing: SlotSizing.intrinsic,
    builder: (context) => const Text('Horloge'),
  ),
);
```

`component.createSlot(id, visible: condition)` permet de masquer un slot selon
l'état de l'application ; `visible` vaut `true` par défaut.

Une fabrique crée son widget dans le contexte de la zone, sans conserver une
instance partagée. `isAvailable` filtre les composants selon les ancêtres du
layout (et non ceux du dialogue de sélection). `slotId` permet de conserver un
identifiant de placement historique ; sinon un identifiant de registre est
généré. Un composant dont le `slotId` est déjà fourni dans `slots` n'est pas
ajouté une seconde fois au sélecteur. L'enregistrement d'une clé de composant
déjà utilisée et la résolution d'une clé inconnue lèvent une `StateError`.

`SuperApp` prend en charge la restauration et la sauvegarde de l'apparence, le
reset des dispositions, la mise à jour de la transparence de fenêtre ainsi
qu'une coquille `MaterialApp` avec le mode d'édition et le fond stylé :

```dart
const SuperApp(home: MyHomePage(), title: 'Mon application')
```

Un `AppearanceStore` personnalise peut etre fourni via `appearanceStore`.
Son `AppearanceCodec` definit les valeurs par defaut, le format/version JSON,
la validation, les migrations et les preferences supplementaires. Une
application peut etendre `Appearance` en preservant son type dans `copyWith`
et fournir un codec type, sans importer cette application depuis le package.
Le codec injecte est aussi transmis aux dialogues d'import/export par
`AppearanceServicesScope`. Le package utilise sa propre cle
`super_container_layout.appearance` et un schema generique version 1 ;
il ne lit ni ne supprime les preferences d'une autre application.

Les anciens formats ne sont jamais jetes automatiquement : un codec qui
retourne `needsMigration == true` les valide avant de sauvegarder la valeur
migree. Les erreurs sont signalees par `SuperApp` et par le controleur, sans
effacer le document original. Les ecritures sont serialisees et validees.

`AppearanceSettings` fournit thème, accent et transparence de fenêtre.
Avec `DefaultAppearance`, il fournit aussi dimensions, espacement, texte,
icônes et fondu de défilement (ces sections sont absentes avec `Appearance`).
Injecter `slots: List<AppearanceSlot>`, `additionalSections` (des
`AppearanceSettingsSection(id:, label:, icon:, builder:)`), `previewBuilder`
et `defaults` pour composer le panneau sans dépendance métier.
`additionalControls` reste compatible pour les contrôles intégrés au panneau.
`AppearanceStyleSection` conserve les éditeurs de styles, variantes
sélectionnées, fond et effet natif. Les callbacks des slots définissent leur
lecture/écriture et réinitialisation ; des defaults explicites restaurent
les entrées du catalogue, supprimant les variantes facultatives absentes.
`AppearanceSettings.show` capture le contrôleur et `AppearanceServicesScope`
du contexte appelant, avec un thème réactif dans chaque sous-dialogue.
`dialogWrapper` permet de transmettre d'autres scopes : capturer leurs
contrôleurs avant l'ouverture puis retourner le scope autour de `child`.
`resetAdditional` remplace le reset du codec ; sans override, le codec est
appelé une seule fois avant l'application des defaults d'apparence.
`AppearanceTransfer` accepte un codec optionnel pour l'export et l'import
des groupes Styles et Dispositions.

`Registry.layoutController(id)` et `styleController(id)` sont lies au
controleur d'apparence par `SuperApp`, suivent restauration/reinitialisation
et persistent leurs modifications par identifiant.
`SuperApp.of(context).getLayoutConfigById(id)` utilise ce meme lien.
Utilisez un `ValueListenableBuilder` pour afficher un controleur de registre.
Des slots et composants conservant leurs identifiants retrouvent leurs
placements lors du redemarrage.

Pour valider le package sans l'application :

```powershell
cd packages\super_container_layout
flutter pub get
flutter analyze
flutter test
```

Le runner Windows compile `windows\window_transparency.cpp` et enregistre
le canal generique `super_container_layout/window_transparency`.

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
