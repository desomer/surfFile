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

Dans l'application de démonstration, la barre d'apparence en haut à droite
se déplace en faisant glisser la poignée à six points placée avant les boutons.
Elle reste dans les limites de la fenêtre, y compris après redimensionnement.

En édition, les labels des composants de `SuperLayout` partagent le même
badge en modes **Zones** et **Grille** : icône `drag_indicator`, fond
`tertiaryContainer` et angles arrondis. Le glisser-déposer conserve les règles
propres à chaque mode.
L'icône de déplacement apparaît uniquement sur les composants déplaçables.
Les badges utilisent un texte de 10 px et une icône de déplacement de 12 px,
même lorsque le label est tronqué. Les actions des zones restent compactes
(24 px, icônes de 14 px).
Le curseur affiche une main ouverte au survol des labels déplaçables et une
main fermée pendant leur déplacement.
Dans le menu contextuel d'édition, une icône de 12 px avant le titre indique
ce qu'ouvre le clic sur le libellé : palette pour le style, engrenage pour les
paramètres. Elle ne constitue pas un bouton supplémentaire et conserve le
badge du composant et les actions existantes. Les entrées désactivées
n'affichent pas cet indicateur. `EditorMenuDestination` permet de déclarer
la destination d'un éditeur personnalisé via `menuDestination` sur
`EditorSlot`/`EditableSurface`, ou `destination` sur une action/entrée de menu.
Sur Windows natif, où Flutter ne gère pas ces deux curseurs, une main de
pointage apparaît au survol et le curseur de déplacement pendant le glisser.
En mode édition, un clic sur le contenu sélectionne sa zone englobante.
Un double-clic sélectionne uniquement l'enfant direct sous le pointeur ;
les doubles-clics suivants descendent progressivement dans les zones et les
composants imbriqués, sans sauter de niveau. Deux clics isolés ne font pas
descendre la sélection. En mode Grille, la grille joue le rôle de zone.
Le survol indique la prochaine cible par un contour plein pour une zone,
ou pointillé pour un enfant. Les labels conservent leur sélection explicite,
les boutons restent utilisables et un glisser ne déclenche pas de sélection.
Les poignées de redimensionnement des composants sont de petits carrés de
8 px, placés aux coins et au milieu des côtés. Leur zone de saisie reste de
32 px pour faciliter le glisser, y compris dans les grilles et les zones natives.
En mode Zones, le survol d'un label change la couleur des badges des composants
de sa zone sans les grossir ; le grossissement des labels de zones est conservé.
En mode Grille, le survol ou le glisser d'un label met en couleur les badges
de tous les composants de cette grille, sans modifier leur taille.
Les labels des zones affichent aussi `drag_indicator`, uniquement lorsque
leur déplacement/échange est autorisé ; le centre et les zones non déplaçables
n'affichent pas cette icône.

## Text : affichage ou saisie

`Registry.bootstrap(availableFontFamilies: ['Segoe UI', 'Roboto'])` ajoute
`Text` au catalogue avec les tags `text` et `input`. Chaque ajout possède
son propre identifiant et sa propre configuration. Le composant est utilisable
dans les dispositions et les zones internes des barres, mais ne remplace pas
une barre native complète.

```dart
SuperText(
  id: 'customer-name',
  config: const SuperTextConfig(
    mode: SuperTextMode.input,
    initialText: '',
    label: 'Nom',
    placeholder: 'Votre nom',
    minLines: 1,
    maxLines: 3,
  ),
  controller: nameController,
  availableFontFamilies: const ['Segoe UI', 'Roboto'],
  onChanged: (text) => customer.name = text,
)
```

L'application possède et libère le `TextEditingController`. Autre possibilité :
passer `value: name` et `onChanged: (text) => setState(() => name = text)`, sans
controller. Au premier montage, une liaison fournie par l'application est
respectée sans appel de `onChanged`. Sans liaison, le texte initial est utilisé
localement. Le composant fonctionne aussi sans `SuperApp` ; `onConfigChanged`
permet alors de récupérer ses réglages locaux.

En mode édition, le menu natif de saisie (coller, tout sélectionner, etc.) est désactivé sur
le composant afin de laisser la place au menu d'édition. Il reste disponible
hors édition et dans l'aperçu de configuration ; la saisie et la sélection de
texte ne sont pas désactivées.

En mode édition, clic droit puis **Texte** ouvre la configuration :
affichage/saisie, texte initial, label, placeholder, activé, lecture seule,
mot de passe, lignes min/max et typographie (famille, taille, graisse, italique,
couleur AARRGGBB, alignement, interligne et espacement des lettres).
L'éditeur réutilise le panneau de style partagé : navigation par sections,
cartes de réglages, mode dense et aperçu local du brouillon.
Les éditeurs ouverts via `showEditorDialog` masquent temporairement les
overlays d'édition de la page (labels des zones et slots, poignées et contours
de sélection/survol). Le contenu, ses dimensions et la sélection sont conservés.
Les overlays reviennent après la fermeture du dernier dialogue, y compris
avec des éditeurs imbriqués et sans zoom.
Un dialogue d'édition ouvert au-dessus d'un autre se distingue par une
élévation renforcée, une bordure contrastée et un voile assombrissant
l'arrière-plan. Le premier dialogue conserve son style habituel.
À l'ouverture, le cadrage automatique se recalcule sur le composant édité
dans l'espace libre à côté du dialogue, indépendamment du zoom manuel
précédent. Les dialogues imbriqués gardent cette cible même si leur contexte
appartient au dialogue parent ; le zoom manuel reste centré sur le composant.

Sur écran étroit,
la navigation devient une rangée de puces. La couleur propose la même palette,
roue et opacité, ainsi qu'un retour à la couleur du parent.
L'aperçu utilise le texte initial, jamais la saisie courante de l'application.
Les options typographiques vides héritent du style du parent (par exemple le
style du titre dans une AppBar). Le style de police peut être hérité, normal
ou italique ; les anciennes valeurs explicites sont conservées. Les familles disponibles
sont fournies par l'application, sans téléchargement ; une police sauvegardée
mais absente est signalée en édition et doit être remplacée dans le dialogue.

En affichage sans label, le texte est rendu sans décoration de champ ni marge
de saisie. Le contenu est centré verticalement dans la hauteur du slot, notamment
dans le titre d'une SuperAppBar.

**Attention :** sans tableau d'états ni liaison repository, changer le mode ou le texte initial réinitialise la valeur
courante au texte initial. La réinitialisation met à jour le controller fourni
et appelle `onChanged` une seule fois ; avec `value`, le parent doit accepter
la nouvelle valeur. L'activation du mot de passe efface aussi la valeur.
Le mot de passe est masqué dans les deux modes, sur une seule ligne, et
n'autorise aucun texte initial persistant.

Seuls les réglages sont sauvegardés dans `Appearance.textComponents`, jamais
la saisie courante ni le contenu du controller. Pendant l'édition, les réglages
valides modifient en temps réel le composant dans la page, sans attendre
**Appliquer**. Les valeurs invalides sont signalées et le dernier rendu valide
est conservé. Le bouton **Annuler**, à côté d'**Appliquer**, ou la fermeture du
dialogue restaure le composant et sa saisie d'origine (sélection comprise).
Le brouillon utilise un controller temporaire : il ne publie pas de `onChanged`,
ne change pas la liaison active et n'écrit pas dans les repositories.
Seul **Appliquer** sauvegarde les réglages et active une nouvelle liaison.
Une application validée constitue une seule étape d'annulation/rétablissement.
L'annulation des changements de mode/texte initial applique également la règle
de réinitialisation ; elle ne restaure pas les anciennes saisies.
Les réglages texte font partie du groupe **Dispositions** à l'import/export
et sont supprimés par la remise à zéro des dispositions.

### Propriétés du texte par état

La carte **États** utilise `EditorStateControls`, le même sélecteur que les
surfaces éditables : boutons **Par défaut**, **Hover** et **Sélectionné**
(dans une ListView), ajout/renommage/suppression d'états nommés et liaison
en lecture seule à un attribut JSON. Le nom correspond exactement à une chaîne
du repository ; une valeur inconnue conserve les réglages par défaut.
**Sélectionné** dépend uniquement de la ligne de ListView la plus proche,
jamais de la sélection de l'éditeur ; une liste imbriquée masque la sélection
de sa liste parente.

Les surfaces présentent également ces contrôles dans une carte **États**
du panneau de propriétés, et non dans un bandeau au-dessus du panneau.
Les indicateurs de propriétés sont toujours visibles : seul **Par défaut**
est entièrement coché et non modifiable. Pour les états JSON nommés comme
pour les états automatiques, chaque puce permet d'activer ou de désactiver
la surcharge correspondante.

Le bouton **+** ouvre un catalogue contextuel, commun aux surfaces et à Text :

- **Survol du composant** et **ListView sélectionné** ajoutent Hover/Sélectionné
  sur Text : ils ne sont plus présents par défaut et peuvent être supprimés.
  Les définitions déjà configurées restent disponibles. Sur les surfaces,
  ces deux boutons restent permanents. Le menu empêche les doublons.
- **Content survolé** est proposé dans un `IterableContent`. Il suit le survol
  de tout le Content le plus proche, même au-dessus d'un autre enfant ou d'un
  espace vide de la ligne. Deux lignes restent indépendantes ; un Content
  imbriqué masque le contexte de son parent pour ses descendants.
- **Focus du champ**, **Champ désactivé** et **Champ en lecture seule** sont
  proposés uniquement pour Text en saisie.
- **État personnalisé JSON…** conserve la création d'un état nommé.

Un nouvel état automatique est sélectionné et ajouté en fin de priorité avec
une surcharge vide : il ne change rien tant qu'aucun groupe de propriétés
n'est activé. Il peut être déplacé, supprimé et ajouté de nouveau.
Les états non pertinents ne sont pas proposés. Une définition enregistrée
reste conservée mais inactive lorsqu'elle n'est plus applicable.
Les nouveaux états sont persistés dans la map optionnelle `automatic` des
tables d'états, avec des identifiants `AutomaticState` ; les documents
antérieurs restent lisibles sans modification.

Le focus correspond au vrai focus du champ, pas à un descendant arbitraire
d'une surface ni au focus du dialogue d'édition. **Désactivé** et **Lecture
seule** sont évalués à partir du défaut ou de la configuration JSON nommée,
avant toutes les surcharges automatiques. Une surcharge ne réévalue donc pas
son propre déclencheur et ne peut pas provoquer d'oscillation. Le verrou
temporaire de chargement d'une liaison n'est pas un état Désactivé configuré.

`SuperTextConfig.states` contient un `TextConfigStates` : les états nommés
conservent leurs valeurs dans `named` et leurs groupes activés dans
`namedProperties`. Comme Hover et Sélectionné, ils appliquent seulement
les groupes explicitement activés, avec la logique de `TextConfigOverride`.
Les groupes non cochés héritent des valeurs précédentes dans l'ordre des états.
Un état nommé nouveau ou enregistré sans `namedProperties` commence sans
aucune surcharge, toutes les puces décochées. Ses anciennes valeurs sont
conservées et réutilisables en cochant les propriétés.
Toutes les propriétés sont concernées, y compris les liaisons JSON.
Le mode, le contenu initial, le mot de passe, les lignes et toutes les options
du champ forment un groupe **Contenu** indivisible ; activation et lecture seule
forment un autre groupe. Chaque liaison de propriété suit le groupe correspondant.
Modifier une propriété active automatiquement son groupe ; désactiver sa puce
rétablit l'héritage. Les combinaisons invalides bloquent la validation.

Les boutons se déplacent par glisser-déposer pour enregistrer la priorité :
le dernier état actif gagne. Par défaut, les états nommés précèdent Hover,
puis Sélectionné. Par défaut reste toujours la base.
L'aperçu du brouillon ne change ni la sélection réelle ni les données JSON.
**Appliquer** enregistre toute la table en une seule étape d'historique ;
**Annuler** l'abandonne.

Avec un tableau d'états, chaque changement réel d'états actifs réinitialise la
saisie interne : texte initial de la configuration effective, ou relecture de
sa liaison de contenu. Un simple déplacement à l'intérieur du composant ne
réinitialise rien. Cette règle concerne aussi l'entrée/sortie de Focus, sans
faire perdre le focus au champ pendant la saisie.
Les écritures en attente sont capturées sur l'ancienne liaison
avant cette transition ; un survol seul n'écrit jamais dans le repository.
Les chargements et réinitialisations d'état ne publient pas de `onChanged`.
Lorsque la liaison de contenu reste identique, sa relecture de transition
conserve le texte affiché, le focus et l'état activé du champ : aucun passage
intermédiaire au texte initial ou au style désactivé.
Un `controller` ou une `value` externe conserve la propriété du texte et n'est
pas réinitialisé ; dans ce cas, aucune configuration d'état ne peut lier le
contenu à un repository. Les liaisons des autres propriétés restent disponibles.
Une configuration effective invalide fournie de l'extérieur affiche une erreur
et revient aux propriétés par défaut.

### Styles et options du champ de saisie

L'éditeur présente la carte **États**, puis **Repository**, le contenu, le
comportement et la typographie. Les options de saisie sont réparties dans les
cartes **Style du champ**, **Couleurs du champ**, **Préfixes et suffixes**,
**Messages et compteur**, **Limites et filtres** et **Clavier et saisie**,
accessibles directement depuis la navigation.
En mode **Affichage**, ces six cartes de saisie sont masquées, ainsi que les
options lecture seule, activation du champ et lignes minimales. Le repository,
le contenu, le masquage du texte, les lignes maximales et la typographie restent
accessibles. Passer d'un mode à l'autre conserve les réglages du champ ; un
brouillon de saisie invalide masqué ne bloque pas l'application en Affichage.

La carte **Style du champ** propose les styles **Thème** (par défaut), **Filled**,
**Outlined**, **Underline** et **Sans bordure**. Ces réglages ne modifient pas
le mode Affichage. Le thème reste utilisé pour les propriétés non personnalisées.

```dart
const SuperTextConfig(
  mode: SuperTextMode.input,
  label: 'Nom',
  field: SuperTextFieldConfig(
    variant: TextFieldVariant.outlined,
    radius: 12,
    prefixIcon: TextFieldIcon.person,
    suffix: TextFieldSuffix.clear,
    helperText: 'Votre nom complet',
    maxLength: 80,
    showCounter: true,
    capitalization: TextCapitalization.words,
    action: TextFieldAction.next,
  ),
)
```

Les options comprennent :

- Couleurs du fond et des bordures aux états normal, focus, désactivé et erreur
  (y compris l'erreur avec focus), arrondi, épaisseur, marges internes et densité.
- Textes et icônes de préfixe/suffixe, aide, erreur manuelle et label flottant.
  Une erreur de liaison JSON est prioritaire sur l'erreur manuelle.
- Suffixe décoratif, bouton **Effacer** ou bouton de visibilité du mot de passe.
  **Effacer** respecte les états désactivé/lecture seule et publie une seule
  modification, y compris vers un repository. La visibilité reste locale,
  n'est pas sauvegardée et ne réactive ni suggestions ni correction du mot de passe.
- Longueur maximale et compteur facultatifs. Le comptage utilise les graphèmes
  (un emoji composé compte pour un caractère) ; le compteur peut aussi être
  affiché sans limite.
- Filtres : aucun, chiffres, décimal signé avec point, lettres Unicode
  (accents, espaces, apostrophes et tiret), ou expression régulière de caractères
  autorisés, par exemple `[A-Z]`. Le filtre regex n'est pas une validation du texte
  complet. Le filtre décimal accepte les états intermédiaires comme `-` ou `-.`.
- Clavier, action de saisie, capitalisation, alignement vertical, correction
  automatique et suggestions.

Les filtres et limites s'appliquent uniquement aux saisies/collages, après la
composition IME. Ils ne tronquent ni les valeurs du controller ni les données
chargées depuis un repository. Changer les options ne réécrit pas ces données.
L'aperçu utilise le même rendu que le composant, sans accéder au repository.
Les brouillons invalides bloquent **Appliquer** ; **Annuler** ne publie rien.
Ces options suivent la sauvegarde, l'import/export et l'annulation des autres
réglages de SuperText.

### Liaison SuperText / repository JSON

La section **Repository** de l'editeur permet de choisir un document du dossier
par defaut puis un chemin d'attribut, par exemple `client.nom` ou
`clients[0].nom`. **Sans liaison** retire cette association. Le nom facilite
le choix, mais seul l'ID technique est sauvegarde : renommer le repository
ne casse pas les textes lies. Un repository absent ou un ID duplique/corrompu
produit une erreur explicite, sans recherche approximative par ancien nom.

```dart
SuperText(
  id: 'client-name',
  config: SuperTextConfig(
    mode: SuperTextMode.input,
    binding: JsonTextBinding(
      repositoryId: repositoryId,
      path: 'client.nom',
    ),
  ),
)
```

La liaison utilise uniquement le controleur interne de SuperText ; `controller`
et `value` fournis par l'application sont incompatibles avec une liaison.
Le JSON fournit la valeur initiale, en affichage comme en saisie ; changer le
mode ou le texte initial ne remplace plus cette valeur. Les changements de texte
du controleur interne sont enregistres apres une pause de 350 ms, et la derniere
saisie est envoyee a l'ancien attribut lors d'une deliaison ou d'un demontage.
Les changements de selection seuls ne produisent aucune ecriture.

Les chaines, nombres et booleens existants conservent leur type. Les booleens
acceptent `true`/`false` et les nombres la syntaxe JSON ; une saisie intermediaire
invalide reste visible sans ecraser le fichier. Un attribut absent ou `null`
est affiche vide et devient une chaine lors de la saisie ; les objets parents
manquants sont crees a ce moment seulement. Les tableaux ne sont jamais etendus,
leurs indices doivent exister. Les objets/tableaux comme valeurs terminales,
les structures incompatibles et les chemins invalides sont refuses. Les cles
contenant des points ou des crochets et les expressions JSONPath ne sont pas
prises en charge.

`SuperApp` fournit un `JsonRepositoryStore` partage. Une sauvegarde depuis le
gestionnaire actualise les SuperText, et inversement. Les ecritures sont
serialisees ; un changement d'un autre attribut est preserve, tandis qu'un
conflit sur l'attribut lie conserve la saisie locale et affiche une erreur.
**Recharger la liaison** demande confirmation avant d'abandonner cette saisie.
Il n'y a pas de surveillance des fichiers externes : ils sont relus lors de
la prochaine connexion/reouverture, ainsi qu'avant une ecriture pour controler
les conflits.

Pour une integration autonome, placer `JsonRepositoryScope(store: store, child:
...)` au-dessus des textes et du navigateur. `SuperApp(repositoryStore: store,
...)` permet d'injecter le meme service ; l'appelant libere alors ce store.
Le gestionnaire partage celui du scope pour le dossier par defaut et conserve
son fonctionnement independant dans un autre dossier.

**Attention aux mots de passe :** une liaison de champ masque est autorisee,
mais sa valeur est enregistree **en clair dans le fichier JSON**. L'editeur
affiche cet avertissement et son apercu ne lit pas les donnees du repository.
Les valeurs courantes ne sont jamais ajoutees a l'apparence : seuls ID et
chemin y figurent. L'historique annule la configuration de liaison, pas les
donnees deja ecrites dans les repositories ; une page dupliquee garde la meme
reference de repository et ne duplique pas ses donnees.

## Tags des composants et restrictions des zones

Les composants du registre et les slots fournis directement peuvent déclarer
plusieurs `tags`. Les tags décrivent le type de composant, pas ses instances :

```dart
registry.registerComponent(
  'page-title',
  RegisteredComponent(
    label: 'Titre',
    tags: const {'appBar', 'text'},
    builder: (_) => const Text('Titre de la page'),
  ),
);
registry.registerFactory(
  'custom-navigation',
  const MyNavigation(),
  tags: const {'bottomNavigationBar', 'navigation'},
);
```

Les factories dynamiques acceptent aussi `tags` sur `ComponentBuilderDynamic`.
`Registry.bootstrap()` attribue `appBar` à `AppBar`,
`bottomNavigationBar` à `BottomNavigationBar`, `container` à
`Card`, `layout` à `Layout`, et les deux tags `container` et `layout` à `IterableContent`.

Les noms du catalogue, des menus et des types sauvegardes sont `Card`, `Layout`,
`IterableContent`, `Text`, `ListView`, `AppBar` et `BottomNavigationBar` ; le type d'edition d'une
page est `Page`. Les classes et les fichiers Dart conservent leur nom avec
prefixe `Super` (par exemple `SuperContainer`, `SuperLayout`, `SuperText`).
Les anciennes cles de catalogue et de persistance (`NewContainer`, `NewLayout`,
`SuperText`, etc.) ne sont pas conservees comme alias : les documents existants
doivent etre recrees ou leurs types mis a jour.

### Icone dans le menu d'edition

Le parametre optionnel `menuIcon` (`IconData`) de `RegisteredComponent`,
`Registry.registerFactory` et `ComponentBuilderDynamic` definit l'icone de
l'entree du composant dans le menu contextuel d'edition :

```dart
registry.registerComponent(
  'page-title',
  RegisteredComponent(
    label: 'Titre',
    menuIcon: Icons.title,
    builder: (_) => const SuperText(id: 'page-title'),
  ),
);
registry.registerFactory(
  'custom-navigation',
  const MyNavigation(),
  menuIcon: Icons.navigation_outlined,
);
```

Les slots fournis directement acceptent aussi `menuIcon` sur `BuilderSlot`.
L'icone est propre au composant et n'est pas transmise aux cibles d'edition
imbriquees. Sans `menuIcon`, le menu conserve ses icones par defaut
(`Icons.brush_outlined` pour la premiere entree, `Icons.subdirectory_arrow_left`
pour les ancetres). Cela s'applique aux dispositions et aux zones natives.
`Registry.bootstrap()` renseigne une icone pour chacun des composants standards :
texte, barre d'application, navigation inferieure, conteneur, liste et disposition.

### Envelopper un composant

En mode edition, les trois points verticaux en fin de ligne du menu contextuel
ouvrent **Envelopper dans…**, avec **Card**, **Layout** et **IterableContent**.
Ces choix utilisent les factories de meme nom installees par
`Registry.bootstrap()` ; seuls les parents compatibles avec les tags de la zone
sont proposes.

Le nouveau parent remplace le composant a la meme position, y compris en grille,
et reprend ses contraintes de taille et de marge. Le composant devient son
enfant sans changer d'identifiant, de nom personnalise ni de configuration.
L'operation est sauvegardee et constitue une seule etape d'annulation/retablissement.
Elle fonctionne aussi avec les slots et les champs `child` fournis par le code :
leur definition doit rester presente dans le widget d'origine pour les retrouver
au chargement. Les enveloppements successifs sont possibles.

### Styles de surface par état

Toutes les surfaces `EditableSurface` (dont Card et IterableContent) proposent
des boutons de sélection côte à côte : **Par défaut**, les états nommés, **Hover** et,
dans une ligne de ListView, **Sélectionné**. L'état choisi est mis en évidence ;
les boutons passent à la ligne si nécessaire. Les actions permettent d'ajouter,
renommer ou supprimer un état.
Un nouvel état conserve une copie des valeurs du style par défaut, mais commence
sans surcharge. Les propriétés non cochées suivent donc les changements du défaut.
Les anciens états enregistrés sans `namedProperties` commencent également avec
toutes les puces décochées ; leurs valeurs restent disponibles en les activant.

Le bouton de liaison choisit un repository et un attribut JSON, par exemple
`clients[?].statut`. Le repository et les indices peuvent être hérités de la ligne.
La valeur doit être une chaîne correspondant exactement au nom de l'état,
casse comprise. Une valeur absente, nulle ou inconnue utilise le défaut.
Les erreurs de liaison ou de type apparaissent dans l'éditeur, pas dans la page.
Les lectures sont réactives et ne modifient ni le JSON ni l'historique d'apparence.
Renommer un état ne renomme pas les valeurs dans le repository.

**Hover** s'active lorsque la souris survole la surface, y compris ses enfants.
Il se configure comme **Sélectionné**, sans modifier la sélection ou le JSON.
Tous les états nommés ou automatiques sont des surcouches : seules les familles de propriétés activées
par leurs puces remplacent le style courant. Modifier une propriété active sa
famille ; désactiver la puce rétablit l'héritage. Zéro, faux et une couleur
absente sont des remplacements explicites. L'ordre initial est :
**défaut → surcharges de l'état JSON → Hover → Sélectionné**.
Glissez les boutons d'état pour changer leur priorité : parmi les états actifs,
le suivant remplace le précédent. Le défaut reste la base fixe à gauche.
Un état JSON placé après une autre surcouche remplace seulement les groupes
qu'il surcharge explicitement. L'ordre est sauvegardé avec le style, ainsi que
les groupes activés par état dans `namedProperties`.
Dans les listes imbriquées, seule la sélection de la ligne la plus proche compte.
La surbrillance habituelle de la ListView reste présente tant que son gabarit
ne définit aucune propriété de sélection.

Le sélecteur fournit un aperçu local sans changer la sélection réelle ni le JSON.
**Appliquer** conserve les définitions ; **Annuler** les restaure. L'aperçu disparaît
à la fermeture. Le tableau est sauvegardé avec le style et suit sa duplication
et son historique. Les variantes Standard/Sélectionné des `AppearanceSlot`
restent distinctes de ces états. `SuperContainer` seul reste un moteur de rendu :
la résolution des états est assurée par `EditableSurface`.

### IterableContent : surface stylable et disposition

`IterableContent` (nom de catalogue **IterableContent**) compose une surface editable comme
Card et un `SuperLayout` structurel. Deux entrees du menu contextuel separent le
style **IterableContent** de la disposition **Layout**. Le Layout interne n'est pas un
enfant optionnel : on peut y ajouter, deplacer et retirer des slots, mais pas le
supprimer comme le champ enfant d'une Card.

Sans style explicite, IterableContent est transparent, sans marge, padding, bordure ou
ombre. Il prend en charge les memes reglages de `ContainerStyle` que Card :
fond, arrondis, bordures, ombres, effets et espacements. Par exemple :

```dart
IterableContent(
  id: 'article',
  style: const ContainerStyle(radius: 12, padding: 8),
  config: const SuperLayoutConfig(north: false, south: false),
)
```

Avec un registre, le style et la disposition sont sauvegardes sous le meme ID,
respectivement dans `styles[id]` et `layouts[id]`. Sans registre, le composant
conserve des valeurs locales et expose `onStyleChanged` et `onChanged`.
L'ajout au catalogue propose les reglages de style ; le Layout reste editable
apres insertion. Envelopper dans IterableContent place le composant existant au centre
de son Layout et conserve son identifiant et ses reglages.

Les lignes de `SuperListView` utilisent IterableContent. `template` definit leur
disposition et `templateStyle` leur style initial. Toutes les lignes d'une liste,
y compris le gabarit vide, partagent ces reglages ; modifier une ligne met a jour
les autres, meme sans registre. Avec un registre, `styles[listId]` et
`layouts[listId]` appartiennent au gabarit de la liste, sans ID par index.
La copie et la suppression d'une ListView incluent ce style de gabarit.
Les indices JSON, la selection maitre/detail et les controles de retrait restent
propres a chaque ligne. `itemExtent` et `spacing` ne changent pas : les marges et
le padding de IterableContent utilisent l'espace deja attribue a la ligne.

### Mode Wrap de ListView

Les reglages « Liste JSON » proposent Verticale, Horizontale et Wrap.
Wrap dispose les elements de gauche a droite, avec retour a la ligne selon
la largeur disponible et defilement vertical. `spacing` s'applique entre
les elements et entre les rangees, sans espace ajoute en fin de rangee.

Les dimensions ne sont plus dans les reglages « Liste JSON ». Dans le menu
contextuel d'une ligne, l'icone regle sur l'entree de **style Iterable Content**
ouvre **Taille et marge preferees**, la meme fenetre que pour les slots du Layout.
Ce menu et ses actions sont reserves au mode edition. Hors edition, les menus
natifs des composants, notamment la selection de texte, restent disponibles.
Elle definit les largeurs/hauteurs minimales, preferees et maximales en **px**
ou **%**, ainsi que des marges uniformes ou independantes.
Ces reglages sont partages par toutes les lignes, en Wrap, Verticale et Horizontale.
Ils sont enregistres dans `listComponents[listId].itemSize`, sans ID par ligne.

Une dimension preferee vide est automatique selon le contenu (avec les bornes
min/max), tandis qu'une valeur definit une taille preferee. En liste verticale,
une largeur automatique remplit l'espace disponible ; en liste horizontale,
c'est la hauteur automatique. En Wrap, les deux dimensions peuvent etre
automatiques. Un Layout en grille conserve ses colonnes et mesure sa hauteur
selon ses lignes.

Les pourcentages utilisent soit l'espace de la liste, soit le Layout englobant
selon la base choisie. Sans Layout englobant, les deux bases utilisent la liste.
Si sa hauteur n'est pas bornee, la hauteur du viewport de l'application sert
de reference aux pourcentages verticaux.
Les dimensions comprennent les marges ; `spacing` reste ajoute entre les elements.
Les anciens `itemExtent`, `itemWidth` et `wrapSizing` restent les valeurs initiales
tant qu'aucun reglage `itemSize` n'a ete defini.

```dart
const SuperListViewConfig(
  wrap: true,
  itemSize: SlotSizeConstraints(
    preferredWidth: SlotDimension(40, SlotSizeUnit.percent),
    preferredHeight: SlotDimension(100, SlotSizeUnit.pixels),
    padding: 8,
  ),
  spacing: 12,
)
```

Le mode, le choix de taille et les dimensions sont persistants et participent
a l'annulation/retablissement comme les autres reglages de la liste.

Un `ComponentTagFilter` définit les catégories acceptées par une zone :

```dart
const NativeRegion(
  'title',
  'Titre',
  tagFilter: ComponentTagFilter(
    include: {'text', 'navigation'},
    exclude: {'internal'},
  ),
);

SuperLayout(
  zoneTagFilters: const {
    SuperLayoutZone.north: ComponentTagFilter(include: {'appBar'}),
    SuperLayoutZone.center: ComponentTagFilter(exclude: {'internal'}),
  },
  slots: [
    BuilderSlot(
      id: 'header',
      label: 'En-tête',
      tags: const {'appBar'},
      builder: (_) => const Text('En-tête'),
    ),
  ],
);
```

`RegisteredSuperLayout` expose également `zoneTagFilters`. Les filtres des
zones sont attachés à leur destination affichée, même après un échange de
contenus ; le mode grille utilise le filtre de `SuperLayoutZone.center`.

Une liste `include` vide autorise tout sauf les tags exclus. Sinon, au moins
un tag inclus doit correspondre. Un tag exclu est toujours prioritaire.
Un composant sans tag est refusé si `include` n'est pas vide. Sans filtre,
une zone reste libre.

Par défaut, les régions `appBar` et `bottomNavigationBar` de `SuperPage`
acceptent respectivement les catégories `appBar` et `bottomNavigationBar`.
Les widgets fournis directement par ces propriétés restent compatibles avec
leur région. Les autres régions n'ont aucune restriction par défaut.
L'autorisation porte sur le tag, pas sur le nom de classe : un composant
personnalisé tagué `appBar` est donc également accepté.

Les catalogues de l'éditeur sont filtrés et les nouvelles insertions,
changements de type et déplacements incompatibles sont refusés, y compris
après les callbacks d'ajout. Un échange est refusé en entier si l'une des
destinations est incompatible.

En mode édition, faites glisser l'étiquette d'un slot pour le déplacer entre
les régions d'un même composant natif : par exemple `Titre` et `Actions` de
`SuperAppBar`, ou `Gauche`, `Centre` et `Droite` de
`SuperBottomNavigationBar`. Un dépôt sur un autre slot permet de l'insérer
avant ou après celui-ci ; sur l'espace libre, il est ajouté en dernier.
Les régions vides doivent être activées pour recevoir un dépôt. Une région
limitée à un seul slot et déjà occupée refuse le déplacement sans remplacer
son contenu. L'identifiant, le type et les dimensions suivent le slot ; les
déplacements sont sauvegardés et peuvent être annulés/rétablis.
Le glisser-déposer reste limité aux régions du même propriétaire, pas entre
deux barres ou entre une barre et un `SuperLayout`.

Dans **Configurer la barre**, le switch **Bouton de navigation par défaut**
laisse Flutter afficher le bouton du drawer ou, sans drawer, le bouton Retour
si la route le permet. Il reste visible en mode édition. Lorsque ce switch est
activé, la zone **Navigation** n'est ni proposée dans les réglages, ni affichée,
ni disponible pour un dépôt. Ses slots restent sauvegardés et réapparaissent
en désactivant le switch si la zone est active.
Sans préférence sauvegardée, le comportement natif est utilisé quand
`automaticallyImplyLeading` l'autorise et qu'aucun slot Navigation n'est placé
ou explicitement désactivé ; les anciennes navigations personnalisées restent
donc inchangées. Le choix est persisté dans
`NativeComponentConfig.useDefaultNavigation`, transféré avec les dispositions
et compatible avec l'annulation/rétablissement.

Dans les barres natives, cliquez sur l'étiquette d'un slot en mode édition
pour afficher ses poignées de redimensionnement. Les dimensions sont limitées
à l'espace disponible dans la région ; redimensionner un slot n'agrandit pas
la hauteur fixe de la barre. Les dimensions sont sauvegardées et un geste
complet peut être annulé/rétabli en une seule opération.

L'éditeur de taille est commun aux zones de `SuperLayout`, aux régions
natives de la page et aux barres : il propose les largeurs et hauteurs
minimales, préférées et maximales, en pixels ou en pourcentage. Les
pourcentages se rapportent au choix à la zone ou au composant parent.
Il conserve l'aperçu en direct, les curseurs, la validation min/max,
le retour à une taille automatique et l'annulation des changements.

Dans la grille, l'éditeur « Position et taille » conserve les coordonnées
et dimensions en cellules. Son bouton « Tailles min / préférée / max »
ouvre le même formulaire pour dimensionner le contenu du slot dans sa
cellule, sans déplacer ni agrandir celle-ci. La base « zone » correspond
alors à la cellule ; la base « layout » à la surface visible du layout.
Les contraintes de contenu restent enregistrées lors d'un changement de mode.

Les documents existants restent lisibles : un ancien placement incompatible
reste affiché, redimensionnable, réordonnable dans la même zone et supprimable.
Il peut être déplacé vers une zone compatible. Les restaurations et
undo/redo ne suppriment pas ces anciens placements.
Tags et filtres restent des métadonnées du code ; ils ne sont pas édités dans
l'interface ni enregistrés dans le JSON. Les configurations manipulées
directement par le code ne valident pas le catalogue ; les contrôles
s'appliquent aux mutations de l'éditeur.

## Gestion des pages depuis l'editeur (optionnelle)

Le bouton **Gerer les pages** du bandeau d'edition est active uniquement si
`SuperApp` recoit un registre et un `EditorPageRouter`. L'application reste
proprietaire du routeur et le libere a sa fermeture :

```dart
final pageRouting = EditorPageRouter(
  baseConfig: RoutingConfig(routes: [
    GoRoute(path: '/', builder: (_, _) => const SuperPage()),
  ]),
);

SuperApp(
  router: pageRouting.router,
  pageRouting: pageRouting,
  registry: Registry()..bootstrap(),
);

// A la fermeture de l'application : pageRouting.dispose();
```

Sans cette integration, `SuperApp(router: router)` garde son comportement
habituel. Elle est activee dans la demo du package, pas dans SurfFile.
Les routes codees sont listees en lecture seule pour etre ouvertes depuis le
gestionnaire ; leurs chemins et leur configuration restent modifiables uniquement
dans le code de l'application.

Le dialogue permet d'ajouter des `SuperPage` vides et configurables, modifier
leur nom et leur chemin URL, les dupliquer, supprimer, ordonner, choisir
l'accueil et les ouvrir. Les changements restent locaux jusqu'a **Appliquer**,
qui constitue une seule etape d'annulation/retablissement. **Annuler** abandonne
le brouillon. **Ouvrir** demande d'abord de valider un brouillon modifie.
Une modification externe des dispositions est signalee : rechargez alors le
brouillon plutot que d'ecraser les changements.

Les chemins utilisent la syntaxe du GoRouter installe, notamment
`/clients/:id` et `/clients/:id(\d+)`. L'ouverture demande des valeurs concretes
et verifie les contraintes. Toutes les valeurs d'un meme chemin partagent le
meme design. Pour une page d'accueil parametree, les valeurs par defaut valides
sont enregistrees. L'accueil remplace seulement `/` au demarrage ; une URL
profonde explicite reste prioritaire. Renommer le chemin de la page courante
conserve ses parametres si possible ; sinon, ou apres sa suppression, une
notification explique le retour a l'accueil.

Les collisions avec les routes codees et les autres pages sont refusees.
Pour les expressions regulieres, la validation est volontairement prudente :
si l'absence de chevauchement ne peut pas etre prouvee par les prefixes
litteraux, le chemin est refuse meme si les expressions semblent disjointes.
Utilisez des prefixes distincts, par exemple `/clients/:id` et `/help/:topic`.
Le chemin `/` reste reserve a la route racine codee.

`Appearance.pageCatalog` est sauvegarde avec les dispositions, inclus dans les
imports/exports et supprime par la remise a zero des dispositions. Les anciens
documents restent compatibles. Une duplication copie les configurations et
styles persistants du graphe de composants, avec de nouveaux identifiants ;
elle ne copie ni controllers, ni saisies courantes, ni donnees metier.
Les composants personnalises doivent declarer explicitement leur contrat de
duplication dans le registre ; sinon l'operation est refusee sans copie partielle.

Par exemple, un composant sans configuration persistante peut autoriser la
copie de son placement :

```dart
registry.registerComponent(
  'badge',
  RegisteredComponent(
    label: 'Badge',
    builder: (_) => const Text('Badge'),
    duplication: const ComponentDuplicationContract.stateless(),
  ),
);
```

Pour un composant qui possede des configurations derivees de son identifiant,
utilisez `ComponentDuplicationContract(ownedConfigs: (id) => [
EditorConfigRef.text('$id.title'), EditorConfigRef.style('$id.surface')])`.
Ces references doivent correspondre exactement aux identifiants utilises par
son builder, dans le meme ordre pour chaque instance. Le contrat peut fournir
`copyConfig: (source, value, remap) => ...` pour remapper des references internes
personnalisees ; la copie structurelle standard suffit aux configurations
integrees. Une suppression conserve les configurations encore partagees par
d'autres pages et signale les donnees personnalisees dont la propriete n'est
pas declaree.

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

### Zones natives de page

`SuperPage` rend ses zones directement dans les proprietes du `Scaffold` :
`appBar`, `body`, `drawer`, `endDrawer`, `bottomNavigationBar`,
`floatingActionButton` et `bottomSheet`. Il n'enveloppe plus la page dans un
`RegisteredSuperLayout`. Les drawers restent donc geres par le `Scaffold`,
y compris leur ouverture, leur fermeture et le glissement depuis le bord.
`bottomBar` reste un alias de compatibilite de `bottomNavigationBar`.

```dart
SuperPage(
  id: 'explorer-page',
  appBar: SuperAppBar(
    id: 'explorer-appBar',
    title: const Text('Explorateur'),
  ),
  drawer: const Drawer(child: ExplorerNavigation()),
  child: const ExplorerContent(),
  bottomNavigationBar: const ExplorerBottomBar(),
)
```

`slots` ajoute des `SlotImplementation` au catalogue local. En mode edition,
le clic droit sur une region (Corps, AppBar, drawers, etc.) propose son entree :
cliquer sur son nom ouvre la configuration de page. Ses switches activent ou masquent
les regions natives sans supprimer leurs slots. Le corps reste toujours actif.
Il n'y a pas d'entree « Configurer la page… » supplementaire. Le bouton « + »
de chaque entree ajoute un slot dans la region ; Fond conserve son editeur de style.
Les entrees de region affichent le `label` de `SuperPage` (par defaut `Page`)
en gras, suivi du nom de la region. Ce label est aussi utilise dans le chemin
de selection de la banniere.
Chaque region active affiche son nom selectionnable, son contour et son propre
bouton « + ». Activer un drawer dans ce panneau l'ouvre a la fermeture du panneau.
Les overlays ne sont visibles que lorsque la page ou la region est selectionnee.
Selectionner une disposition enfant masque les overlays de la page ; le chemin
de la banniere inclut `Page > region > disposition` et permet de revenir au parent.
Les boutons du corps permettent ensuite de rouvrir les drawers actifs.
Hors edition, les regions vides ne prennent aucune place. Les activations sont
persistees avec les placements et prennent en charge annulation/retablissement.
Le corps peut etre remplace ou vide. Dans la demo, les commandes d'edition et
d'apparence sont donc placees hors de `SuperPage`, pour rester accessibles
independamment des slots sauvegardes.
Les regions qui contiennent plusieurs slots les composent avec `SlotStack`.
Dans les regions peripheriques, les slots `fill` sans `preferredSize` sont
dimensionnes par defaut a la hauteur d'une barre basse (barre de navigation
et panneau bas) ou a 56 x 56 pour le bouton flottant. Une disposition imbriquee
ne peut ainsi pas absorber toute la hauteur du corps. Les slots intrinsèques
et les tailles preferees explicites conservent leur dimensionnement.
`pageConfig` fournit les placements initiaux avec `ScaffoldPageRegion` :

```dart
SuperPage(
  id: 'custom-page',
  slots: [
    BuilderSlot(
      id: 'navigation',
      label: 'Navigation',
      builder: (_) => const ExplorerNavigation(),
    ),
  ],
  pageConfig: ScaffoldPageConfig(
    placements: {
      ScaffoldPageRegion.drawer: ['navigation'],
    },
  ),
)
```

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
Avec `SuperApp(registry: registry, router: router)`, activez le mode edition
puis ajoutez-le dans la region `appBar`. Les regions non configurees restent
vides et n'occupent pas d'espace ; le body conserve le contenu `child`.

`SuperAppBar` utilise directement `AppBar.leading`, `title`, `actions`,
`bottom` et `flexibleSpace`, sans `RegisteredSuperLayout`. `action` reste
un raccourci compatible pour la premiere action ; `actions` accepte une liste
native. Le titre compose ses slots horizontalement avec `SlotStack`.
Navigation, Bas et Espace flexible acceptent un seul slot : un ajout y remplace
le precedent en une operation annulable. Le bas est adapte en
`PreferredSizeWidget` ; `SuperPage` suit ses changements de hauteur pour
preserver la place du corps.

Le clic droit n'importe ou sur la barre, meme vide ou sur un bouton natif,
propose **AppBar** Configurer la barre et selectionne l'AppBar dans le chemin
de la banniere. Cette entree permet d'activer les premieres regions d'une
barre ajoutee depuis le catalogue.
Le clic droit sur une region ouvre aussi un menu avec **AppBar** et son nom.
Cliquer le nom ouvre les cinq switches de configuration. Les badges, ajouts,
tailles preferees en pixels, suppressions et chemins de selection utilisent
le meme editeur que la page. Entrer dans l'AppBar masque les overlays de page ;
revenir au segment Page les retablit. Les regions masquees gardent leurs slots.
Le bouton de retour automatique est conserve tant que Navigation n'a pas ete
explicitement desactivee ; desactiver Actions supprime aussi les actions
automatiques de Flutter.

### Adaptateurs de composants natifs

`SuperBottomNavigationBar` est une barre basse a widgets libres, rendue avec
un vrai `BottomAppBar` (pas une liste de `BottomNavigationBarItem`).
Ses regions `left`, `center`, `right` affichent Gauche, Centre et Droite.
Chaque region accepte plusieurs slots horizontaux. Les regions visibles se
partagent la largeur a parts egales ; hors edition, les regions vides ne
reservent pas de largeur. La hauteur de contenu est bornee a 56 par defaut
(`height`), meme lorsque la barre est vide, sans reduire le corps a zero.
`BottomAppBar` gere la zone sure inferieure native.

```dart
SuperPage(
  bottomNavigationBar: SuperBottomNavigationBar(
    id: 'explorer-bottom-bar',
    left: IconButton(icon: const Icon(Icons.home), onPressed: goHome),
    center: const Text('Explorateur'),
    right: IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
  ),
)
```

Depuis le catalogue, ajouter `SuperBottomNavigationBar` dans la region
Barre basse de la page. En edition, le clic droit sur la barre, meme vide,
propose « Configurer la barre basse » avec trois switches. Les badges
Gauche / Centre / Droite et leurs boutons + utilisent le meme editeur que
l'AppBar. Masquer une region conserve ses slots ; les modifications sont
persistantes et annulables. `slots`, `nativeConfig` et `onNativeSlotAdded`
permettent de personnaliser le catalogue et les placements initiaux.
Chaque instance doit avoir son propre `id`. Les callbacks de navigation
restent portes par les widgets fournis.

`NativeComponentConfig` fournit un modele immutable commun : regions actives,
placements ordonnes, types de slots et preferences de dimensions.
`NativeRegion` decrit chaque propriete : nom stable, label, cardinalite,
axe, contraintes de remplissage et taille du placeholder.
`NativeComponentEditor` partage selection hierarchique, menu contextuel,
switches, catalogue local/registre, ajouts et suppressions.
L'adaptateur construit toujours le vrai widget Flutter ; il ne simule pas
sa disposition. Les listes natives, comme `AppBar.actions`, restent natives.

`Registry.nativeComponentController(id)` raccorde ces configurations a
`Appearance.nativeComponents`, a la sauvegarde, au groupe de transfert
Dispositions et a l'historique. Utiliser des IDs distincts pour chaque instance,
y compris entre pages et barres. `ScaffoldPageConfig` et
`Registry.scaffoldPageController` restent des facades typees compatibles sur
ce modele et ce stockage communs. Les anciennes collections `scaffoldPages`
et les anciens layouts d'AppBar Centre/Est sont lus sans effacement ; la
prochaine edition de l'instance ecrit sa configuration native.
Un ancien layout d'AppBar utilisant d'autres zones est signale explicitement.
`SuperAppBar.config` et `onSlotAdded` sont conserves pour compatibilite ;
preferer `nativeConfig` et `onNativeSlotAdded` pour les nouveaux composants.
Les anciennes contraintes de taille sont conservees en lecture.

Pour ajouter un composant, declarer ses `NativeRegion`, fournir ses slots et
construire son widget dans le builder de `NativeComponentEditor`.
`editor.region(id)` compose les slots ; `editor.region(id, item: slot)` permet
de decorer chaque element d'une liste native. Un composant a hauteur editable
peut implementer `NativePreferredSizeWidget` pour que son parent suive
`preferredSizeIn(context)` et `sizeListenable(context)`.
Les donnees qui ne sont pas des widgets (par exemple les
`BottomNavigationBarItem`) necessitent un adaptateur type specifique.
Les callbacks et l'etat de navigation restent controles par l'application,
jamais serialises dans les placements.

En mode edition, `SuperPage` centre automatiquement la disposition, la zone
ou le slot selectionne. La molette ajuste le zoom en mode edition lorsqu'une
selection est active : vers le haut pour zoomer, vers le bas pour dezoomer
(de x1 a x3), avec animation et une sensibilite reduite. A x1, la page
retrouve sa position normale ; le cadrage se rapproche progressivement de la
selection jusqu'au centrage a x3. Le cadrage automatique des dialogues peut
toujours descendre sous x1 pour laisser le composant visible. Une nouvelle
selection ou la sortie du mode edition retablit le cadrage automatique.
Les zones defilantes gardent la priorite pour leur propre defilement.
Le clic droit selectionne la zone sous le pointeur avant d'ouvrir le menu,
y compris dans les layouts imbriques et apres zoom. Les actions de chaque
layout parent ciblent egalement sa zone situee sous ce clic.
Le zoom vise 70 % de la largeur et de la hauteur de
l'ecran, sans reduction et avec un agrandissement limite a x3. La transition
dure 300 ms ; la deselection ou la sortie du mode edition retablit la vue
normale avec la meme animation. Les preferences d'accessibilite demandant
moins d'animations sont respectees.
La banniere, les labels, les commandes de redimensionnement, les menus et
les dialogues gardent leur taille a l'ecran. Les labels et commandes suivent
les nouvelles positions du contenu. Le zoom ne modifie pas les tailles
enregistrees des slots.

Quand son `SuperLayout` est deja selectionne en mode edition, un clic sur
le contenu d'un slot selectionne ce slot. Cliquer de nouveau sur le contenu
le garde selectionne ; son label permet toujours de basculer la selection.
Le premier clic sur une disposition non selectionnee active uniquement
la disposition. Les glissers et clics droits ne selectionnent pas le slot,
et les boutons du composant conservent leur action.
Revenir sur une disposition parente, par clic ou via le fil d'Ariane,
deselectionne les zones et slots de toutes ses dispositions descendantes,
y compris celles qui ne sont pas actives.
Changer de disposition par clic efface aussi la zone et le slot memorises
de la disposition activee : le zoom cible d'abord la disposition entiere.

Les dispositions libres restent sauvegardees via `Registry.layoutController`.
Les placements de `SuperPage` sont distincts et sauvegardes via
`Registry.scaffoldPageController`. Donnez un `id` stable et distinct a chaque
page. La reinitialisation des dispositions restaure les placements initiaux ;
les imports/exports de dispositions incluent aussi les regions Scaffold.
Sans registre, les slots fournis restent utilisables mais les changements de
placement ne sont pas persistants.

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
`SuperLayoutConfig`. `SuperContainer` assure uniquement le rendu des styles,
éventuellement partagés via `AppearanceScope` et `AppearanceSlot`.
`EditorSlot` porte les interactions d'édition et `EditableSurface` compose les
deux pour proposer une surface décorée et éditable.

### Décoration et édition indépendantes

```dart
// Rendu seul : aucun menu ni enfant catalogue, même en mode édition.
const SuperContainer(
  style: ContainerStyle(radius: 12),
  child: Text('Décoration seule'),
);

// Édition seule : aucune surface décorative n'est ajoutée.
EditorSlot(
  label: 'Mon composant',
  onEdit: openComponentSettings,
  child: const Text('Contenu'),
);

// Composition : style local ou AppearanceSlot, aperçu et annulation.
EditableSurface(
  label: 'Mon panneau',
  slot: customSlot,
  child: const Text('Surface éditable'),
);
```

`StyleEditScope`, `EditorSlot` et les contrats `EditorSlotAction` et
`EditorContextMenuEntry` se trouvent dans `widgets/editing/slots/`. Le menu remonte
la chaîne des `EditorSlot` éditables et conserve les actions de taille et de
suppression sur la cible concernée. La sélection métier des zones reste dans
les layouts et l'éditeur natif ; le survol et les commandes sont communs.

Migration : remplacer les anciens `SuperContainer` éditables par
`EditableSurface`, et les enveloppes `decorate: false` servant uniquement au
menu par `EditorSlot`. Les accès programmatiques au menu passent désormais par
`EditorSlotState`, et l'édition du style par `EditableSurfaceState`.
Les imports directs d'édition ne proviennent plus de
`widgets/surfaces/super_container.dart`.

Les widgets sont classes par role sous `lib/widgets/` :

- `appearance/` : reglages d'apparence, sections de styles et dialogue de transfert.
- `editing/` : editeurs de styles, controles, banniere et historique d'edition.
- `surfaces/` : conteneurs, rendu des surfaces, effets d'interaction et painters.
- `super_layout/` : disposition, slots, selection, axes et raccourci de reinitialisation.

Le dossier `editing/` est organise par responsabilite :

| Sous-dossier | Contenu |
| --- | --- |
| `addition/` | Wizard d'ajout et configurateurs des composants |
| `components/` | Editeurs Texte, Liste et reglages du champ texte |
| `dialogs/` | Ouverture des dialogues et en-tete partage |
| `history/` | Historique, transactions et controles d'annulation |
| `overlay/` | Overlays, zoom, poignees et banniere du mode edition |
| `pages/` | Gestionnaire des pages |
| `repositories/` | Gestionnaire des repositories JSON |
| `slots/` | Cibles d'edition, menu, surfaces editables, enfants, taille et suppression |
| `styles/` | Dialogue et panneau de style, controles et editeur de decoration |

Les imports directs utilisent ces sous-dossiers. Les exports du point d'entree
`super_container_layout.dart` restent disponibles sans changement d'import
pour les utilisateurs de cette facade.

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
Le slot selectionne affiche huit poignees a fleches : diagonales aux coins,
horizontales et verticales au milieu des cotes (une seule dimension modifiee).
Les pastilles de 24 px ont une zone de saisie de 32 px, une couleur accentuee
au survol et un tooltip. La taille en pixels s'affiche pendant le glissement.
Ces controles restent sans zoom. Les poignees apparaissent lorsque la
disposition est editable. Elles restent au-dessus des noms de zones pour
ne pas etre masquees. Leur position est calculee pendant le layout pour
permettre l'affichage des tooltips au survol. Leur glisser ajuste ses tailles preferees en temps
reel, sans le deplacer dans la zone. Les bornes min/max, l'espace disponible
et les minima des autres slots sont respectes ; les unites px/% et la base
des pourcentages sont conservees. Les modifications passent par `onChanged`
et chaque glisser constitue une seule operation dans l'historique d'edition.
Les poignees disparaissent a la deselection et hors du mode edition.

### Positionnement Zones ou Grille

L'editeur de `SuperLayout` propose un selecteur **Zones / Grille**.
Le mode Zones conserve les reglages Nord/Sud/Est/Ouest, les coins, les axes
et les tailles preferees px/%. Le mode Grille utilise des cellules entieres
`x`, `y`, `width`, `height`, sans chevauchement.

La grille demarre avec 12 colonnes, des lignes de 64 px et un espacement de
8 px. Ces reglages et le compactage vertical sont editables. La largeur des
cellules suit la largeur disponible ; la hauteur du contenu peut depasser
le layout et defiler verticalement. Les controles overlay sont limites a la
partie visible du layout et restent a l'echelle de l'ecran.

- Le premier passage en Grille reprend tous les slots places, y compris
  ceux des zones masquees. Les composants non disponibles restent dans la
  configuration mais ne sont pas construits, comme en mode Zones.
- Les deux dispositions sont conservees separement : changer de mode ne
  remplace ni les placements Zones ni leurs tailles px/%.
- Un ajout recoit un placement dans les deux modes (Centre pour un ajout
  depuis la Grille). Une suppression retire l'instance des deux dispositions.
- En edition, glisser le label deplace le slot ; les huit poignees ajustent
  son rectangle en cellules. La grille, le surlignage de destination et les
  dimensions en cellules accompagnent le glissement.
- Le slot manipule a priorite ; les collisions poussent les autres vers le
  bas. Le compactage vertical optionnel s'applique a la fin du glissement.
- Le menu de taille ouvre un formulaire de position/dimensions en cellules,
  avec renommage, validation et preview en direct. Les bornes px/% du mode
  Zones ne s'appliquent pas a la Grille.
- Selection, zoom, menus de style, sauvegarde JSON et historique restent
  disponibles. Un glissement ou un dialogue applique constitue une operation
  d'historique ; Annuler restaure la configuration initiale.

`SuperLayoutConfig.positioning` vaut `SuperLayoutPositioning.zones` par
defaut, y compris pour les anciens documents JSON. `withPositioning` prepare
la grille lors de la premiere bascule :

```dart
final gridConfig = zoneConfig
    .withPositioning(SuperLayoutPositioning.grid);
final customGrid = gridConfig.copyWith(
  grid: gridConfig.effectiveGrid
      .withColumns(6)
      .copyWith(rowHeight: 80, gap: 12),
);
```

`GridLayoutConfig` sauvegarde les parametres et les `GridSlotPosition` par ID.
Les layouts enregistres utilisent leur sauvegarde habituelle ; pour un
`SuperLayout` autonome, conserver la configuration recue via `onChanged`.
Cette premiere version utilise un nombre de colonnes commun a toutes les
largeurs, sans configurations par breakpoint ni transfert entre grilles.
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

L'editeur de style propose un bouton Mode dense / Mode complet. Le mode dense
masque la preview et remplace les libelles du menu de gauche par des icones
avec une largeur de contenu du dialogue reduite de 1080 a 680 px maximum
(toujours adaptee a l'ecran). Le retour au mode complet restaure la largeur.
Les icones conservent leurs infobulles, meme sur ecran etroit. Les cartes de reglages et la remise
a zero restent accessibles. `ContainerStyleEditor(dense: true)` permet de
demarrer le mode panneau (`collapsible: false`) directement en mode dense ;
`StyleEditorPanel` expose aussi ce parametre. Sans valeur explicite, le dernier
mode choisi est memorise pendant la session et repris aux ouvertures suivantes,
meme pour un autre composant ou un style partage. La largeur du dialogue de
composant suit le mode memorise. Le mode complet reste le defaut initial ;
ce choix n'est pas conserve apres un redemarrage de l'application.
Le nom du composant et le bouton Mode dense / Mode complet partagent le meme
en-tete. Le crayon permet de renommer l'instance ; la coche valide le nom
(non vide), sans modifier son identifiant technique ni son style partage.
Les dialogues de taille et de layout utilisent le meme en-tete editable.
Les noms sont conserves dans `SuperLayoutConfig.slotLabels` et `label`, suivent
les deplacements et sont inclus dans la sauvegarde, l'export et l'historique.
Annuler le dialogue restaure le nom initial. Les menus, labels et chemins de
selection utilisent le nom personnalise. Les titres fonctionnels des dialogues
d'apparence, d'ajout et de transfert restent non editables ; l'editeur d'un
style partage ne renomme pas les instances.
Hors d'un slot de layout, `EditableSurface.onLabelChanged` permet au proprietaire
de sauvegarder le nom puis de le fournir via `label` ; sans callback, le nom
reste local a l'instance. `ContainerStyleEditor.onLabelChanged` permet aussi
d'integrer l'en-tete editable dans un editeur personnalise.

Le bouton **Repository**, a cote de **Gerer les pages** dans la banniere
d'edition, ouvre un gestionnaire de documents JSON libres, independants des
pages et des styles. Chaque repository est un fichier `<nom>.json` : il peut
etre cree, renomme, consulte et modifie. Le dossier initial est
`%USERPROFILE%\.super_container_layout\repositories` sous Windows
(`$HOME/.super_container_layout/repositories` ailleurs) ; le champ du dossier
permet de charger un autre repertoire. Les fichiers sont conserves au
redemarrage et ne sont pas inclus dans la reinitialisation ou l'historique
de l'apparence. **Enregistrer** valide le JSON avant toute ecriture ;
**Formater** l'indente. Un JSON invalide sur disque reste ouvrable pour le
corriger. Les erreurs de fichier et les conflits avec des modifications
externes sont affiches, et l'abandon des modifications demande confirmation.
`JsonRepositoryManager(store: JsonRepositoryStore(Directory(...)))` permet
d'ouvrir le gestionnaire avec un dossier explicite dans une integration.
Chaque repository possede aussi un ID technique genere automatiquement,
affiche en lecture seule et accessible via `JsonRepositoryStore.idOf(name)`.
Il reste identique apres modification du JSON, renommage et redemarrage.
Cet ID est conserve dans un fichier compagnon `<nom>.json.id`, hors du JSON
editable ; deplacer ou sauvegarder un repository doit inclure les deux fichiers.
Les repositories existants recoivent un ID au premier acces, sans modification
de leur contenu. Un fichier d'ID corrompu est signale, jamais regenere en silence.

En mode edition dans une `SuperPage`, les dialogues de style, de taille,
de configuration du layout, d'ajout de slot et d'apparence utilisent un panneau
a droite. Un bouton permet de le placer a gauche. Le composant edite est cadre
avec animation dans l'espace restant, avec dezoom sous x1 si necessaire.
Sur un ecran de moins de 900 px de large, le panneau passe en bas et le composant
au-dessus. Le cadrage suit les modifications de taille du composant, le mode
dense et les redimensionnements de fenetre, sans modifier la disposition
enregistree ni agrandir les overlays d'edition. La banniere reste dans l'espace
libre pour ne pas intercepter les boutons du dialogue. Fermer un dialogue restaure le
cadrage precedent (ou celui du dialogue parent). Les dialogues d'apparence
cadrent la selection active ; sans page zoomable en mode edition, les dialogues
conservent leur presentation classique centree.

L'editeur des tailles des slots propose une preview proportionnelle du layout,
de la zone et du slot, avec les dimensions preferees et effectives en pixels.
Les limites min/max apparaissent en pointilles. Deux sliders, horizontal pour
la largeur et vertical pour la hauteur, pilotent le groupe Min/Preferee/Max
selectionne et restent synchronises avec les six champs numeriques et l'unite
px/%. Chaque champ dispose d'un bouton pour effacer uniquement sa contrainte.
Les nouveaux reglages utilisent par defaut la base « Toute la place du layout »
pour les pourcentages ; une base de zone deja enregistree reste conservee.
Les bornes min/max incompatibles sont signalees et ne sont pas appliquees.
Les valeurs valides,
les unites et la base des pourcentages mettent a jour le rendu en temps reel.
Appliquer conserve les modifications ; Annuler ou fermer le dialogue restaure
les reglages initiaux du slot. Un champ vide reste automatique/non renseigne.
Les sliders couvrent 0-100 % ou la dimension du layout en pixels,
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
zone du layout selectionne. Les zones vides comme remplies affichent un badge
avec le nom selectionnable et un bouton « + » a sa droite. L'icone indique l'axe actuel et
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

Lors d'un ajout dans un `SuperLayout`, la largeur preferee est initialisee
pour Est/Ouest, et la hauteur preferee pour Nord/Sud : la premiere preference
definie par un autre composant visible de la zone est reprise, sinon 20 %
avec la base « Toute la place du layout » (largeur ou hauteur totale du `SuperLayout`).
L'autre dimension et les bornes existantes sont conservees. Une preference
en pourcentage est reprise avec sa base, sauf si elle modifierait la base
de bornes ou d'une autre dimension deja en pourcentage. Dans ce cas, la valeur
par defaut de 20 % et la base « Toute la place du layout » sont appliquees ; cette base
est commune a toutes les dimensions en pourcentage du slot. Centre et coins
restent inchanges. Cette regle concerne les ajouts de l'editeur, pas les
placements initiaux, les deplacements par glisser-deposer ou les preferences
deja enregistrees.

`onSlotAdded` permet de remplacer cette regle sur `SuperLayout`,
et `RegisteredSuperLayout`. Sur `SuperAppBar`, utiliser `onNativeSlotAdded` ;
son ancien `onSlotAdded` reste adapte pour Titre et Actions uniquement.
Le callback synchrone des layouts
recoit l'identifiant de l'instance, le composant, la zone visuelle, la zone de
contenu, les composants visibles deja presents et la configuration contenant
le nouvel ajout. Il retourne la configuration a enregistrer ; placement et
taille forment une seule modification annulable.

```dart
SuperLayout(
  slots: slots,
  onSlotAdded: (addition) {
    final config = SuperLayout.defaultSlotAddition(addition);
    if (addition.zone != SuperLayoutZone.east) return config;
    return config.copyWith(
      slotSizeConstraints: {
        ...config.slotSizeConstraints,
        addition.slotId: const SlotSizeConstraints(
          preferredWidth: SlotDimension(300, SlotSizeUnit.pixels),
        ),
      },
    );
  },
)
```

Pour desactiver l'initialisation automatique :
`onSlotAdded: (addition) => addition.config`.
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
EditableSurface(slot: customSlot, child: const Text('Mon panneau'));
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

En mode édition, les zones de `SuperLayout` affichent leur nom et un bouton « + »
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
    {"type": "registry:Layout", "id": "t1OTp3MeR9"}
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
`New Container`. Cette derniere cree une `EditableSurface` vide et editable,
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

### Ajouter un enfant dans une EditableSurface

En mode édition, un clic droit sur **New Container** affiche un bouton **+**
sur sa ligne dans le menu contextuel. Il ouvre le catalogue des composants
(fabriques et composants enregistrés disponibles), comme dans les zones natives.
Le conteneur possède un seul enfant : s'il est déjà rempli, une confirmation
**Remplacer** est demandée avant le choix. Annuler l'une des deux fenêtres
conserve le contenu actuel. La suppression de l'enfant apparaît sur sa propre
ligne de menu ; elle reste sur le parent si l'enfant n'a pas de cible d'édition.

Pour activer ce comportement sur un conteneur déclaré dans le code, fournissez
un `id` stable et unique sous `SuperApp` :

```dart
const EditableSurface(
  id: 'customer-panel',
  label: 'Panneau client',
  // child est facultatif ; s'il est fourni, il devient le contenu initial.
);
```

L'enfant choisi et son identifiant d'instance sont sauvegardés dans
`Appearance.nativeComponents[id]`, région `child`. Ils suivent l'import/export
des dispositions, la remise à zéro, l'annulation/rétablissement et la duplication
des pages, y compris les enfants imbriqués. Les conteneurs du catalogue activent
automatiquement cette fonction. Sans `id`, le `child` reste géré uniquement par
l'application, sans nouvel ajout interactif ; un `onAdd` explicite garde la
priorité sur le sélecteur intégré. Hors `SuperApp`, le contenu reste local et
aucun catalogue partagé n'est disponible.

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
Le menu **Couleur d'accent** regroupe le sélecteur de couleur et l'opacité
de la fenêtre ; l'alpha de la couleur et l'opacité globale restent indépendants.
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
