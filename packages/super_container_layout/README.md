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
  router: router,
  appearanceStore: AppearanceStore(codec: const DefaultAppearanceCodec()),
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

## Pages et routage

`SuperApp` exige toujours un `GoRouter` et utilise exclusivement
`MaterialApp.router`. Le parametre `home` et le constructeur
`SuperApp.router` sont supprimes : utilisez `SuperApp(router: router)`.

`SuperPage` fournit un `Scaffold` commun, avec un contenu `child` et une
`appBar` optionnels. Sans contenu, `const SuperPage()` fournit la page racine
vide par defaut. Declarez-la sur `/` dans le routeur fourni ; les routes ne
sont pas ajoutees ni modifiees automatiquement par `SuperApp`.

Pour utiliser le routage declaratif, ajoutez `go_router` aux dependances de
l'application et fournissez un routeur a `SuperApp` :

```dart
import 'package:go_router/go_router.dart';
import 'package:super_container_layout/super_container_layout.dart';

final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SuperPage(),
    ),
    GoRoute(
      path: '/details/:id',
      builder: (context, state) => SuperPage(
        id: 'details',
        child: MyDetailsContent(id: state.pathParameters['id']!),
      ),
    ),
  ],
);

SuperApp(
  router: router,
  appearanceStore: AppearanceStore(codec: const DefaultAppearanceCodec()),
);
```

Depuis une page, `context.go('/details/42')` change de route et
`context.push('/details/42')` permet de revenir avec `context.pop()`.
Les pages routees conservent les scopes d'apparence, le registre, les raccourcis
et la banniere d'edition. Le chargement et les erreurs de restauration sont
affiches avant le contenu route, sans perdre l'URL demandee. La banniere utilise
le navigateur racine de `GoRouter` pour ouvrir les dialogues.

Creez le routeur une seule fois (par exemple dans l'etat de l'application),
pas dans `build`. L'application reste responsable de son `dispose` ;
`SuperApp` ne le detruit pas. Pour personnaliser la page racine, fournissez
par exemple `SuperPage(child: MyHomeContent())` dans le builder de `/`.
L'application SurfFile et la demonstration du package utilisent cette route
racine avec leur contenu existant.

### Slots de page et barre d'application

`SuperPage` utilise un `SuperLayout` avec trois zones nommees :
`appBar` (Nord), `body` (Centre) et `bottomBar` (Sud). Les parametres
`appBar`, `child` et `bottomBar` fournissent les composants initiaux.
`slots` ajoute des `SlotImplementation` au catalogue local et `config`
permet de definir leurs placements initiaux.

```dart
SuperPage(
  id: 'explorer-page',
  appBar: SuperAppBar(
    id: 'explorer-appBar',
    title: const Text('Explorateur'),
    action: IconButton(
      icon: const Icon(Icons.refresh),
      onPressed: refresh,
    ),
  ),
  child: const ExplorerContent(),
  bottomBar: const Text('Pret'),
)
```

Chaque `Registry()` enregistre automatiquement le composant `SuperAppBar`.
Avec `SuperApp(registry: registry, router: router)`, activez le mode edition,
selectionnez la disposition de la page, puis ajoutez ce composant dans
`appBar`. Cette zone et `bottomBar` sont vides par defaut et n'occupent
aucune hauteur hors edition. Le body conserve le contenu `child`.

`SuperAppBar` fournit une barre Material avec deux zones : `title` (Centre)
et `action` (Est). Les parametres `title` et `action` fournissent chacun un
slot initial ; les composants du registre peuvent aussi etre ajoutes depuis
l'editeur. Les emplacements peuvent accueillir plusieurs composants, comme
les autres zones de `SuperLayout`. La zone action est horizontale et sa
largeur s'adapte au contenu. Le bouton de retour automatique est conserve.
En mode edition, le clic droit sur la barre ou ses composants propose la
taille preferee et la suppression des slots dans le menu contextuel.
Le menu cible uniquement le slot le plus proche du clic, sans cumuler les
icones de ses slots parents. Sur une partie vide de la barre, ces actions
ciblent le slot de la barre dans la page, meme lorsque sa disposition interne
est selectionnee.

Les dispositions sont sauvegardees dans les preferences via
`Registry.layoutController`. Donnez un `id` stable et distinct a chaque
page et barre configuree dans le code (`root` et `root-appBar` par defaut).
Une barre ajoutee depuis le registre utilise l'identifiant unique de son
instance : plusieurs barres ont des dispositions independantes.
La reinitialisation des dispositions restaure leurs placements initiaux ;
l'historique et les imports/exports utilisent le mecanisme existant.
Sans registre, les slots fournis restent utilisables mais les changements
de disposition ne sont pas persistants.

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

Les widgets sont classes par role sous `lib/widgets/` :

- `appearance/` : reglages d'apparence, sections de styles et dialogue de transfert.
- `editing/` : editeurs de styles, controles, banniere et historique d'edition.
- `surfaces/` : conteneurs, rendu des surfaces, effets d'interaction et painters.
- `super_layout/` : disposition, slots, selection, axes et raccourci de reinitialisation.

Le point d'entree public `super_container_layout.dart` reste inchange.
Les imports directs de widgets utilisent desormais ces sous-dossiers.
La bibliotheque `lib/widgets/super_layout/super_layout.dart` regroupe
son implementation en fichiers `part` dans
`lib/widgets/super_layout/` : `layout.dart` (widget public, etat et cycle de vie),
`layout_view.dart` (construction des zones et overlays),
`layout_slots.dart` (resolution et affichage des slots),
`layout_dialogs.dart` (dialogues d'edition et d'ajout de slots),
`slot_size_editor.dart` (editeur des tailles min/max/preferees, unites et
base des pourcentages),
`label_scope.dart` (selection des dispositions imbriquees), `zone_layout.dart`
(mesure et rendu des zones), `zone_interactions.dart` (etiquettes et cibles de
depot), `zone_resize_handle.dart` (poignees de redimensionnement) et
`layout_editor.dart` (formulaire d'edition). Ces fichiers partagent
la meme bibliotheque Dart afin de garder les classes internes privees.

En mode edition, cliquer sur le label d'un slot le selectionne et affiche
le chemin disposition > zone > slot dans `StyleEditBanner`. Un second clic
sur le meme label deselectionne le slot. Les segments du chemin permettent
de revenir a la zone ou a la disposition ; le glisser des labels est conserve.
Cliquer sur le segment courant du chemin le deselectionne : un slot revient
a sa zone, une zone a sa disposition, et une disposition quitte la selection.
Cliquer sur un segment parent le selectionne.
Le slot selectionne affiche quatre poignees dans ses coins lorsque la
disposition est editable. Elles restent au-dessus des noms de zones pour
ne pas etre masquees. Leur position est calculee pendant le layout pour
permettre l'affichage des tooltips au survol. Leur glisser ajuste ses tailles preferees en temps
reel, sans le deplacer dans la zone. Les bornes min/max, l'espace disponible
et les minima des autres slots sont respectes ; les unites px/% et la base
des pourcentages sont conservees. Les modifications passent par `onChanged`
et chaque glisser constitue une seule operation dans l'historique d'edition.
Les poignees disparaissent a la deselection et hors du mode edition.
Les nouvelles dispositions utilisent la taille automatique par defaut pour
les quatre cotes (Nord, Sud, Est, Ouest). Pour demander des cotes fixes dans
le code, fournissez `SuperLayoutConfig(autoSides: {})`, ou activez/desactivez
la taille automatique par cote dans l'editeur. Les dispositions sauvegardees
conservent leurs reglages ; les anciens documents sans `autoSides` restent
en taille fixe.

Hors edition, un cote en taille automatique sans slot visible occupe zero
pixel ; les slots masques ou introuvables ne comptent pas comme du contenu.
Les tailles fixes restent reservees, meme pour une zone vide. Les cotes
automatiques retrouvent leur taille de repere en mode edition, y compris
dans les dispositions non selectionnees, sans modifier la configuration.
Un cote necessaire a un coin contenant un slot visible conserve son espace.
Les separateurs de redimensionnement des cotes automatiquement vides sont
masques hors edition.
L'entree contextuelle du SuperLayout affiche le nom de la zone active entre
le label de la disposition et ses boutons d'action (axe, ajout de slot).

L'editeur des tailles des slots propose un slider pour chaque dimension,
synchronise avec le champ numerique et l'unite px/%. Les valeurs valides,
les unites et la base des pourcentages mettent a jour le rendu en temps reel.
Appliquer conserve les modifications ; Annuler ou fermer le dialogue restaure
les reglages initiaux du slot. Un champ vide reste automatique/non renseigne.
Les sliders couvrent 0-100 % ou au moins 0-1000 px (et la dimension du layout),
avec extension de la plage si une valeur saisie depasse ce maximum.

L'editeur propose une activation du glisser separee pour chaque cote et un
interrupteur pour tous les cotes, desactives par defaut. Les reglages sont
persistes dans `SuperLayoutConfig.sideResizing` ; sans reglage individuel,
`resizeSides` reste utilise pour les anciennes configurations.
Une fois active, le bord interieur
de 5 px des zones Nord, Sud, Ouest et Est devient une poignee de type SplitView,
y compris hors du mode edition. Les coins et le centre n'ont pas de poignee ;
les dispositions non editables n'en affichent pas. Le glisser part de la
taille effectivement affichee, passe le cote en taille fixe et transmet les
modifications par `onChanged`. Les tailles sont limitees a 20–400 px et
conservent au moins 20 px pour le centre lorsque l'espace le permet.
L'option et les tailles sont conservees lors d'une sauvegarde ou d'un export.
Chaque poignee affiche trois petits points et deux triangles.
La bordure et les boutons sont mis en surbrillance au survol avec les couleurs
du theme et retrouvent leur couleur normale lorsque la souris sort.
Le triangle est affiche a 15 px dans une zone cliquable de 15 x 15 px sur fond contraste,
sans elargir la bordure de glissement de 5 px. Le triangle
dirige vers l'exterieur reduit la zone a zero, meme si ses composants ont un
minimum. Le separateur reste accessible et le contenu conserve son etat.
Lorsque la zone est reduite, sa bordure est alignee sur le bord du SuperLayout
sans decalage ; les boutons restent a l'interieur pour permettre la restauration.
L'autre triangle restaure la taille precedente si la zone est reduite, sinon
il l'agrandit au maximum autorise par les contraintes et l'espace disponible.
La restauration respecte les limites actuelles. L'etat reduit et la taille
a restaurer sont sauvegardes dans `SuperLayoutConfig.collapsedSides`.
Les min/max renseignes dans `slotSizeConstraints` des composants visibles de
la zone limitent aussi le glisser : somme sur l'axe d'empilement, intersection
sur l'axe transversal. Un maximum absent dans une pile laisse son maximum
total non borne ; un minimum absent contribue zero. Les pourcentages de zone
sont resolus sur la taille candidate, ceux du SuperLayout sur sa taille totale.
Les tailles preferees ne constituent pas des bornes. Si les contraintes sont
incompatibles entre elles ou avec l'espace disponible, le glisser ne modifie
pas la taille de la zone.

En mode edition, les overlays (noms de zones, boutons « + », etiquettes de
slots et cibles de depot) ne sont affiches que pour le `SuperLayout` selectionne.
Un clic gauche sur son contenu le selectionne et deselectionne les autres
dispositions. Dans des layouts imbriques, le plus profond sous le pointeur est
selectionne ; les boutons du contenu conservent leur action habituelle.
Un clic sur un segment du chemin de la banniere selectionne egalement la
disposition correspondante et affiche ses overlays ; un segment de zone
selectionne cette zone dans sa disposition.
Les zones vides affichent le cadre du placeholder uniquement en mode edition,
meme dans les dispositions non selectionnees. Son texte est masque quand le
bouton d'ajout de slot est affiche.
L'entree du layout dans le menu contextuel propose aussi un bouton « + » en
mode edition : il ouvre le choix de slot pour la zone selectionnee, ou le
Centre si aucune zone n'est selectionnee. Le nom ouvre toujours l'editeur.
Un bouton d'axe permet de basculer entre Row et Column dans ce menu et dans
la banniere (zone selectionnee, ou Centre par defaut), ainsi que sur chaque
zone contenant des slots dans le layout selectionne. Les zones vides gardent
uniquement le bouton « + ». L'icone indique l'axe actuel et
l'info-bulle precise l'axe cible. Ces actions utilisent la configuration
persistante de la zone et ne sont disponibles que pour les layouts editables.

Les slots et les `RegisteredComponent` acceptent `preferredSize: Size(largeur,
hauteur)`. En mode edition, le clic droit sur un slot ajoute une icone de
reglage des tailles et une icone « Supprimer le slot » sur la premiere ligne
de style du menu contextuel, sans entree de taille separee. L'icone de tailles
ouvre le dialogue qui regle les tailles
minimale, préférée et maximale, en pixels ou en pourcentage de la zone qui
contient le slot ou de tout le `SuperLayout` (base sélectionnable dans le
dialogue). Chaque dimension peut utiliser son unité. Les contraintes
minimales et maximales sont appliquees même aux slots de taille intrinsèque ou
`fill`; une taille préférée reste facultative. Le bouton « Supprimer le slot »
de la ligne de style retire le slot du
layout et efface ses reglages de taille et de type d'instance. Le composant
reste disponible pour un nouvel ajout. Le dialogue permet aussi de retablir
la taille automatique, meme si le slot declare une taille
preferee par defaut.
En mode edition, le survol d'une ligne du menu contextuel souligne son
conteneur cible avec le contour d'edition. La surbrillance suit la ligne
survolee, y compris ses icones, et disparait a la fermeture du menu.
Les dimensions sont limitees par la zone disponible ; des tailles preferees
qui depassent ensemble l'axe principal de la zone sont reduites
proportionnellement. Les slots
sans taille preferee conservent leur comportement `fill` ou `intrinsic`.
Les modifications passent par `onChanged` et sont persistees par ID d'instance
dans `SuperLayoutConfig.slotPreferredSizes` pour les anciennes tailles en
pixels, ou `slotSizeConstraints` pour les contraintes et dimensions en
pourcentage, y compris apres deplacement, sauvegarde ou export de la
disposition. Une entree `null` dans `slotPreferredSizes` force le mode
automatique ; une entree absente utilise `SlotImplementation.preferredSize`.

L'editeur de disposition propose un selecteur **Row / Column** pour chacune
des neuf zones (desactive si la zone est absente ou fusionnee). `Column` reste
la valeur par defaut. `SuperLayoutConfig.withAxis(zone, Axis.horizontal)`
active `Row` ; `axisOf(zone)` lit l'axe de la zone affichee. Les axes sont
persistes dans `zoneAxes` sous la forme `"north": "row"` ou `"center": "column"`.
Ils suivent le contenu lors d'un echange de zones. Les slots `fill` se partagent
l'espace sur l'axe choisi, les tailles preferees et les cotes automatiques
restent pris en compte, et le glisser-deposer utilise gauche/droite en `Row`
ou haut/bas en `Column`.

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
désactivé, et ne sont visibles que dans la disposition selectionnee.
Le fond des boutons « + » est translucide (35 % d'opacite), sans attenuer
leurs icones ni modifier leur zone cliquable.
Les etiquettes des zones (Nord, Sud, etc.) utilisent la meme transparence,
y compris pendant le glisser-deposer ; leur texte reste opaque.

Si le `SuperApp` possède un `registry`, le sélecteur propose aussi ses composants
sous le nom `Registre : <clé>`. Ils deviennent des slots déplaçables du layout,
identifiés par `registry:<clé encodée comme composant URI>` (préfixe répété si
un slot fourni utilise déjà cet identifiant). Ces identifiants sont enregistrés dans `placements` via
`onChanged` ; conserver les mêmes clés de registre et identifiants de slots
permet de restaurer la disposition. Choisir un composant du registre cree une
nouvelle instance avec un ID persistant ; plusieurs instances du meme type
peuvent coexister. Le glisser-deposer deplace une instance sans changer son ID.
Les slots fournis explicitement restent uniques et sont deplaces par le selecteur.

Dans le JSON, chaque placement contient le type de fabrique et l'ID d'instance :

```json
"placements": {
  "center": [
    {"type": "registry:New%20Layout", "id": "t1OTp3MeR9"}
  ]
}
```

`placements` conserve les listes d'IDs dans l'API Dart, et `slotTypes` associe
les IDs a leurs types (`slotTypeOf(id)`). `withSlotMoved(..., type: ...)` ajoute
une instance ; sans `type`, il conserve celui du slot deplace. Les anciennes
chaines JSON restent lisibles avec `type == id`. Les layouts imbriques utilisent
l'ID persistant de leur placement pour retrouver leur configuration. Un ancien
ID aleatoire de layout absent de son placement ne peut pas etre reconstitue.

Le contenu d'une zone utilise `SuperLayoutState.searchSlot(id)` pour ne creer
que les slots demandes par `placements`. La liste complete reste reservee au
selecteur d'ajout. La recherche conserve les identifiants historiques, les
regles de collision et le filtre `isAvailable` du composant recherche ; elle
renvoie `null` pour un identifiant inconnu.

```dart
final registry = Registry();
registry.registerFactory('horloge', const Text('Horloge'));
SuperApp(registry: registry, home: const SuperLayout());
```

Le registre accepte aussi des fabriques avec `registerComponent` :

`Registry()..bootstrap()` enregistre les fabriques `New Layout` et
`New Container`. Cette derniere cree un `SuperContainer` vide et editable,
dont le style est sauvegarde sous l'ID persistant du placement. Plusieurs
instances conservent ainsi des styles independants.

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

La banniere `StyleEditBanner` se deplace par glisser-deposer, notamment depuis
son titre « Mode édition ». Elle reste dans les limites de la fenetre, meme
lors d'un redimensionnement. La position est conservee tant que le widget reste
monte (y compris en quittant puis en reactivant le mode edition), sans sauvegarde
dans les preferences. Les boutons et les segments du chemin restent cliquables.

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
