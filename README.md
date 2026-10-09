# SurfFile

L'adaptation entre le contrôleur `DefaultAppearance` et les widgets génériques
est fournie par `TypedAppearanceScope` dans le package. Le scope SurfFile garde
uniquement la composition des préférences métier, du codec et du catalogue
de valeurs par défaut ; il ne contient plus d'adaptateurs de contrôleur.

Le modèle réutilisable `DefaultAppearance` appartient au package
`super_container_layout` et est utilisé directement, sans sous-classe applicative.
`SurfFileAppearanceDefaults` contient uniquement les constantes du catalogue
et les valeurs par défaut. `SurfFilePreferences` est un modèle immuable indépendant
pour les jauges et les transitions de dossiers. Le codec SurfFile conserve le
format de sauvegarde actuel et ses migrations historiques.

Un explorateur de fichiers de bureau Flutter.

## Catalogue des styles

`lib/theme/surffile_appearance_slots.dart` definit les slots de style de SurfFile
(`SurfFileAppearanceSlots.background`, `sidebar`, cartes, dossiers, disques,
etc.) et la liste `values`. Le package ne fournit plus ces slots predefinis.
Les instances du catalogue sont des singletons `static final` ; les widgets
qui les utilisent ne sont donc pas des expressions `const`.
Le fond declare le role generique `AppearanceSurfaceRole.applicationBackground`
au lieu d'etre reconnu par une comparaison a un slot particulier.
Les fonctions de lecture, ecriture, remise a zero et les variantes selectionnees
restent disponibles. Le package stocke maintenant les styles et dispositions
dans des collections immuables indexees par identifiants stables, sans preference
d'explorateur, de carte, de dossier ou de disque.

### Preferences et migration

`lib/theme/surffile_appearance.dart` définit les constantes
`SurfFileAppearanceDefaults`, la configuration explicite du catalogue et les
fonctions `cardColor`, `defaultCardColor` et `foregroundForCard`. Les dimensions,
polices et le fondu utilisent directement `DefaultAppearance`. Les styles
(`card`, `selectedCard`, `diskTile`, etc.) et dispositions (`explorer`,
`explorerMain`, `explorerSidebar`) restent indexés par identifiant.
`SurfFilePreferencesScope` expose séparément les préférences métier.
`super_container_layout` fournit les dialogues `AppearanceSettings` et
`AppearanceStyleSection` : thème, accent, dimensions, texte/icônes, fondu,
transparence et éditeur de slots. `lib/widgets/dialogs/appearance_settings.dart`
est un adaptateur : catalogue, aperçu de carte, valeurs par défaut et animation
de navigation. Son wrapper capture `SurfFilePreferencesScope` pour toutes les
sous-fenêtres ; le package capture le contrôleur, le codec et le thème vivant.
La réinitialisation appelle une seule fois le reset métier du codec, puis
applique les valeurs d'apparence par défaut via le contrôleur existant.

`SurfFileApp` injecte `SurfFileAppearanceStore` et `SurfFileAppearanceCodec` dans
`SuperApp`. La cle existante **`appearance.v1` est conservee**. Les documents
historiques plats versions 1 et 2 sont valides, puis migres vers la version 3 :
champs de theme/fenetre, `styles`, `layouts`, et preferences `application`.
Aucune preference valide n'est remise a zero ; les variantes nulles conservent
leur heritage. Une erreur de lecture ou de validation est affichee et le
document invalide reste intact jusqu'a une reinitialisation explicite.
Les deux contrôleurs partagent un seul document et une seule file de sauvegarde :
chaque modification capture immédiatement l'apparence et les préférences métier.
Les erreurs de sauvegarde des jauges/transitions sont signalées comme celles des
styles. Charger, importer et réinitialiser restaure les deux modèles ; remettre
les dispositions à zéro conserve les préférences métier et rétablit le catalogue
des dispositions de l'application.

L'import/export utilise le meme codec : les exports v3, les anciens exports
`surf_file.appearance` v2 et les documents bruts sont acceptes. Les groupes
Styles (y compris les preferences metier) et Dispositions restent independants.
Un import historique partiel ne modifie que les valeurs fournies. Les
identifiants de styles/dispositions generiques supplementaires sont conserves
au prochain enregistrement.

## Registre des composants

`SurfFileApp` cree le registre une seule fois et appelle
`registerExplorerComponents`. Le catalogue dans
`lib/widgets/explorer/explorer_components.dart` contient les composants de la
page (`explorer_sidebar`, `explorer_main`), les barres (`explorer_toolbar`,
`explorer_breadcrumbs`, `explorer_view_mode_bar`, `explorer_filter_bar`,
`explorer_sort_header`, `explorer_split_indicator`), le contenu
(`explorer_content`) et les blocs du panneau gauche
(`explorer_sidebar_places`, `explorer_sidebar_disks`).

Chaque `ExplorerPane` fournit un `ExplorerScope` pour la navigation et un
`ExplorerPaneScope` avec un instantane type (`ExplorerPaneData`) et ses commandes
(`ExplorerPaneActions`). Le panneau fournit un `ExplorerSidebarScope` equivalent.
Les fabriques du registre construisent directement les composants depuis ces
donnees, sans callbacks `WidgetBuilder` fournis par la page ; les deux volets
restent independants. Tous les identifiants historiques de placement sont conserves pour
restaurer les dispositions existantes. Le bouton « + » propose ces composants
uniquement sous un contexte explorateur, sans doublonner les slots deja fournis
au layout. Un `ExplorerPane` utilise sans registre d'application cree un
catalogue local equivalent ; un registre fourni doit enregistrer tout le catalogue.
`ExplorerComponentScope` fournit uniquement la disponibilite et la visibilite
locales a chaque disposition. La creation des slots passe par le registre ;
les callbacks et la logique de navigation restent dans leurs proprietaires.
Le selecteur est limite aux composants de la disposition courante pour eviter
les compositions recursives. Les vues liste/grille, colonnes et carte thermique
restent des variantes du composant `explorer_content`, avec les etats de chargement,
d'erreur et de dossier vide, les transitions et les apercus texte/image/video.
Les blocs espace/favoris et disques sont des composants presentationnels du panneau.
Les cles des apercus et du contenu restent detenues par le volet ; les dispositions
continuent d'etre sauvegardees par le controleur d'apparence.

## Installateur Windows (Inno Setup)

Prerequis : Flutter 3.44.0 ou plus recent (Dart 3.12.0 ou plus recent),
Visual Studio avec les outils C++ de bureau, et Inno Setup 6.
Pour installer ce dernier : `winget install --id JRSoftware.InnoSetup --exact`.
Depuis la racine du projet, executer dans PowerShell :

```powershell
.\installer\build-installer.ps1
```

Le script compile en Release puis cree
`build\installer\SurfFile-0.3.2+5-windows-x64-setup.exe`. La version provient de
`pubspec.yaml` ; modifier ce champ avant de publier une nouvelle version.
Les parametres `-FlutterPath`, `-IsccPath` et `-RuntimePath` permettent de
preciser les outils et le dossier des DLL CRT Visual C++ redistribuables x64.
Le script recherche sinon Flutter dans le PATH ou dans le dossier voisin
`flutter`, et les outils Inno Setup / Visual Studio dans leurs emplacements usuels.

L'installateur propose le francais et l'anglais, installe pour l'utilisateur
courant sans elevation dans `%LOCALAPPDATA%\Programs\SurfFile`, ajoute un
raccourci au menu Demarrer et propose un raccourci Bureau optionnel.
Il inclut l'application complete, ses assets/plugins et les DLL CRT x64
app-local. Windows 10 1803 ou plus recent est requis ; la previsualisation
Monaco necessite Windows 10 1809 et le runtime WebView2.
L'AppId reste stable pour les mises a jour ; la desinstallation retire les
fichiers installes, sans effacer les preferences utilisateur.
L'EXE n'est pas signe : Windows SmartScreen peut afficher un avertissement.
Une distribution publique peut necessiter une signature Authenticode.

## Fonctionnalites

Sous Windows, les fichiers et dossiers peuvent etre glisses depuis
l'Explorateur Windows vers le fond du dossier affiche ou vers un dossier en
liste, grille, colonnes ou carte thermique. Le dossier cible est surligne et
une boite de dialogue demande **Copier**, **Deplacer** ou **Annuler**.
Les transferts utilisent le panneau de progression habituel, avec annulation
et suffixe automatique en cas de nom deja present. Les deux volets acceptent
les depots independamment. Les fichiers virtuels (pieces jointes Outlook,
par exemple) ne sont pas pris en charge : le depot doit fournir des chemins
locaux. Reconstruire l'executable Windows pour activer la cible native OLE.
La cible annonce uniquement un effet de copie a Windows ; le deplacement
eventuel est realise par SurfFile apres confirmation, pour que l'annulation
ne puisse pas provoquer de suppression du cote de la source.
Depuis SurfFile, un fichier, un dossier ou une selection multiple peut aussi
etre glisse vers l'Explorateur Windows. Le glissement vers un dossier de
SurfFile ouvre la meme confirmation de transfert. Le mode se regle dans
Parametres d'apparence > Glisser-deposer : « Jamais » (glisser trace toujours
un cadre de selection), « Si selectionne » (seuls les elements deja
selectionnes se glissent, depuis n'importe ou sur la ligne ou la carte) ou
« Depuis le nom et l'icone » (par defaut, comme l'Explorateur : le nom ou
l'icone se glisse meme non selectionne). Ailleurs, glisser trace un cadre de
selection. Un depot a moins de 24 px du point de
depart, ou sur l'un des elements glisses, est ignore.

Le calcul de taille d'un dossier affiche un panneau flottant, comme les copies,
avec le chemin traite, la taille cumulee, le nombre de fichiers et de dossiers
parcourus, le temps ecoule et un bouton d'annulation. La progression reste
indeterminee tant que le total est inconnu ; aucun pourcentage n'est estime.
Les calculs des autres dossiers sont regroupes dans une seule popup cumulative :
taille, compteurs, dossiers termines sur le total et annulation de tous les
calculs, y compris ceux en attente. Les resultats restent visibles jusqu'a leur fermeture, avec les erreurs
et les elements inaccessibles ignores signales pour les tailles partielles.

La previsualisation des videos et fichiers texte/code s'ouvre et se ferme avec
la barre d'espace apres avoir selectionne un fichier pris en charge. La lecture
video demarre automatiquement ; le panneau propose lecture/pause et navigation.
Les fichiers texte sont affiches en lecture seule avec coloration syntaxique
Monaco. Monaco utilise WebView2 et ses assets locaux ; le runtime WebView2 doit
etre installe sur Windows 10 1809 ou plus recent. La lecture video utilise les
codecs Windows disponibles sur le PC ; certains formats peuvent necessiter un
codec supplementaire.

Le menu contextuel utilise des lignes compactes de 32 pixels, des icones pour
les commandes Windows usuelles, des separateurs fins et un panneau arrondi
avec bordure et ombre discrete. Ses couleurs suivent le theme clair/sombre ;
les commandes desactivees, cochees et les sous-menus gardent leurs etats.
Dans ce menu, le bouton lateral Retour remonte au menu parent et ferme le menu
a la racine. Suivant rouvre le sous-menu quitte ; ouvrir un autre sous-menu
efface cet historique. Ces boutons ne naviguent pas dans les dossiers tant
que le menu est ouvert et fonctionnent aussi sur les commandes desactivees.

La zone des fichiers en liste et en grille utilise un fondu transparent de
28 pixels en haut et en bas lorsqu'il reste du contenu dans cette direction.
Le fondu disparait aux extremites et lorsque tout le contenu tient dans la
zone ; il laisse apparaitre le fond personnalise et ne touche pas aux en-tetes.
Le bouton **Fondu des fichiers** des parametres d'apparence permet de le
desactiver ou de regler sa hauteur entre 8 et 100 pixels. Le changement est
immediat, sauvegarde et commun aux vues liste et grille ; la reinitialisation
du fondu restaure uniquement son activation et sa hauteur de 28 pixels.

Le panneau gauche affiche les disques Windows dans une grille de deux colonnes.
Chaque disque indique son pourcentage d'occupation par une piste circulaire et
son espace libre en Gio/Tio ; l'anneau devient rouge a partir de 90 %.
Un clic ouvre la racine du disque et une infobulle detaille sa capacite totale.
Les capacites sont actualisees au retour dans l'application ou manuellement.
Les lecteurs sans media affichent « Indisponible » ; les erreurs de lecture
de la liste proposent de reessayer. La zone est defilante sur les petites fenetres.
Les cles USB, lecteurs optiques et disques durs externes USB/FireWire/SD
affichent un bouton « Ejecter » (jamais le disque systeme ; les disques
externes NVMe/Thunderbolt ne sont pas detectes). L'ejection quitte d'abord le
disque s'il est ouvert, puis demande a Windows un retrait securise ; si des
fichiers sont encore ouverts, un message l'indique.
Cette fonctionnalite utilise les API Windows et necessite une reconstruction
complete apres sa premiere installation, pas seulement un rechargement a chaud.

Pour verifier la vue partagee dans le vrai executable Release (les tests de
widgets seuls ne couvrent pas les crashes AOT), executer :

```powershell
flutter build windows --release --target test\split_release_smoke.dart
& .\build\windows\x64\runner\Release\surf_file.exe
```

Ce test ouvre et ferme automatiquement la vue partagee trois fois, verifie
les deux volets et leur barre d'actions, puis quitte avec le code 0 en cas de
succes. Recompiler ensuite l'application normale avec le script d'installateur
avant de distribuer l'executable.

Le bouton lateral Retour des souris revient au dossier precedent des l'appui,
partout dans l'explorateur. Il reste inactif si l'historique est vide, pendant
un chargement ou lorsqu'un dialogue/menu contextuel est ouvert.
Le bouton lateral Suivant et la fleche Suivant de la barre d'outils permettent
de parcourir l'historique vers l'avant. Ouvrir un nouveau dossier apres un retour
efface cette suite ; actualiser la conserve. Une navigation qui echoue ne
consomme pas l'historique.

La barre de navigation regroupe Retour, Suivant, Dossier parent et Actualiser
dans un bloc arrondi. La recherche dispose d'un contour accentue au focus ;
sur une fenetre etroite, elle passe sur une seconde ligne et la creation de
dossier devient un bouton icone avec infobulle. Le chemin met en evidence le
dossier actif avec une pastille et une icone, et conserve les liens vers les
parents ainsi que ses reglages de couleur, bordure et neon.

L'icone **Parametres d'apparence** de la barre d'outils ouvre un panneau pour
choisir Clair, Sombre ou Systeme et personnaliser les couleurs d'accent, de fond
et des cartes avec **flex_color_picker 4.0.0** : palette, nuances de gris,
roue chromatique et saisie hexadecimale. Le curseur **Opacite** permet de regler
l'alpha des couleurs d'accent, des cartes et du fond, de transparent a opaque.
La transparence est conservee dans les preferences.
Le panneau principal reste compact : des boutons ouvrent des popups dedies
a l'accent, au style des cartes, au fond, aux dimensions, au texte et aux
icones, a la selection et a la transparence de la fenetre. Aucun popup ne
grise l'arriere-plan. Les modifications sont appliquees et sauvegardees en direct.
Les couleurs des cartes et du fond se reglent uniquement dans leur editeur
de style ; arrondi, bordure, elevation generale et ombre ne sont plus dupliques.
Les boutons **Style du panneau de gauche** et **Style de la barre du chemin**
ouvrent aussi l'editeur : couleur unie avec alpha, degrades, arrondi, bordure,
elevation et opacite de l'ombre sont independants pour chacun.
Les textes s'adaptent au fond personnalise, sans modifier la surbrillance du
dossier selectionne. **Couleur unie automatique** suit le theme ;
**Reinitialiser ce style** restaure uniquement le panneau concerne.
Ces reglages sont persistants et les anciennes preferences restent compatibles.
Les sections **Style des cartes** et **Style du fond de l'application**
proposent un fond uni ou un degrade lineaire, radial ou circulaire. Les deux
couleurs (avec alpha), l'orientation et le rayon radial sont editables avec un
apercu. Le fond respecte aussi le curseur d'opacite global. Les cartes en liste
et en grille partagent le meme degrade ; la selection garde sa surbrillance.
Les nouveaux styles sont sauvegardes et les anciens reglages restent compatibles.
Le composant reutilisable `ContainerStyleEditor` dans
`lib/widgets/container_style_editor.dart` recoit un `ContainerFill` et un
callback `onChanged`. Ses callbacks optionnels exposent aussi l'arrondi, la
bordure, l'elevation et l'opacite de l'ombre ; `solidColor` et
`onSolidColorChanged` permettent d'editer la couleur unie.
`neon`, `accent` et `onNeonChanged` exposent l'effet neon et l'integrent a
l'apercu du conteneur. `ContainerStyle.neon` persiste ce reglage pour les
panneaux et les selections ; `StyledSurface` assure leur rendu commun.
Chaque editeur propose aussi **Couleur de la bordure** (avec alpha) et
**Bordure du conteneur** pour son epaisseur de 0 a 4 pixels ; 0 masque la
bordure. **Couleur de bordure automatique** restaure la couleur adaptee au
theme et au panneau. Ces reglages sont independants, persistants et visibles
dans l'apercu, y compris pour le fond de l'application. En liste, les cartes
non selectionnees affichent leur bordure lorsqu'une couleur est personnalisee ;
sans personnalisation, leur apparence historique reste inchangee.
`collapsible: false` affiche directement son contenu dans un popup.
`ContainerFill.gradient()` fournit le rendu Flutter.
Sous Windows, deux curseurs independants reglent l'opacite du fond (0-100 %)
et celle de la fenetre entiere (20-100 %). Le premier permet de voir les fenetres
ou le bureau derriere SurfFile via la composition Windows, sans attenuer le
texte et les icones. Le second attenue toute la fenetre. Les cartes et le menu
lateral gardent leur propre fond. L'effet necessite Windows 10 1803 ou plus
recent et une relance complete apres l'installation de `flutter_acrylic`.
Le mode Systeme suit Windows.
La hauteur et la largeur des cartes, la hauteur des lignes, les arrondis,
l'espacement, l'ombre et son opacite, les bordures, la taille du texte et des
icones sont reglables avec un apercu immediat.
L'elevation des cartes selectionnees (liste et grille) et celle du dossier
selectionne dans le menu de gauche se reglent dans leurs editeurs de style
respectifs, sans bouton d'elevation separe. L'opacite de l'ombre y est aussi
independante. Par defaut, les cartes selectionnees
suivent l'elevation generale et les dossiers du menu restent sans elevation.
Le reglage **Effet neon** est integre a chaque `ContainerStyleEditor` :
cartes, cartes selectionnees, selection du panneau gauche, panneau gauche,
barre du chemin et fond de l'application. Il n'y a plus de bouton dedie dans
le panneau principal. Chaque style a son interrupteur, sa couleur (avec alpha)
et son intensite de 0 a 300 %, avec un apercu commun au fond, a la bordure et au neon.
Au-dela de 100 %, le halo s'etend davantage ; l'opacite reste bornee et
respecte l'alpha de la couleur choisie.
Le neon ajoute uniquement un halo lumineux, sans dessiner une seconde bordure
ni modifier la bordure configuree dans le style. Le halo suit la couleur d'accent
par defaut ; sa couleur (avec alpha) et son intensite sont personnalisables
avec un apercu immediat. Ces options sont sauvegardees et desactivees par defaut,
y compris lors du chargement d'anciennes preferences. **Reinitialiser**
desactive tous les effets. Les anciens reglages neon sont conserves ; les
cartes selectionnees suivent le neon des cartes tant que leur propre style
neon n'a pas ete personnalise.
Les couleurs de texte des cartes s'adaptent a leur fond.
Les boutons **Style des cartes selectionnees** et **Style de la selection du
panneau gauche** permettent de personnaliser independamment le fond uni (avec
alpha) ou degrade, l'arrondi, la bordure, l'elevation et l'opacite de l'ombre.
Le style des cartes selectionnees s'applique en liste et en grille ; celui du
panneau gauche suit le dossier actif. Le texte et les icones du panneau
s'adaptent au fond choisi, et le neon se regle dans le meme editeur.
Les modifications sont immediates et sauvegardees. **Couleur unie automatique**
retrouve la couleur de selection du theme ; **Reinitialiser ce style** supprime
la personnalisation de cette selection sans modifier les autres styles.
Sans personnalisation, les selections conservent leur apparence et leurs
reglages d'elevation existants.
En vue liste, la surbrillance glisse vers la nouvelle ligne selectionnee en
250 ms des l'appui du bouton gauche de la souris, sans attendre son relachement
ni deplacer le contenu. Les preferences systeme de reduction des animations
sont respectees.
Un leger enfoncement accompagne l'appui sur une ligne ou une carte, avec retour
souple au relachement ou a l'annulation du geste. Cet effet respecte egalement
la reduction des animations.
Le tri et le filtrage repositionnent directement
la selection, sans animer vers une autre entree.
**Animation de navigation** propose **Aucune**, **Fondu**, **Glissement**,
**Glissement pleine largeur** ou **Zoom**, avec une duree de 100 a 1000 ms
(220 ms par defaut). Le glissement simple deplace le contenu de 8 % de la
largeur ; le glissement pleine largeur fait entrer le nouveau contenu depuis
le bord oppose sur 100 % de la largeur de la zone des fichiers.
L'ancien dossier reste visible pendant la transition : il sort dans le sens
oppose au nouveau contenu pour le glissement, ou s'efface pour le fondu et
le zoom. Il est non interactif et retire des la fin de l'animation.
Deux variantes **Hero — expansion du dossier** et **Hero — icone vers le titre**
animent le dossier ouvert par double-clic depuis sa position en liste ou en
grille : expansion vers la zone de contenu, ou deplacement de son icone vers
l'icone du titre. Ces effets de type Hero sont realises dans l'explorateur
sans changement de route Flutter. Depuis le panneau gauche, les chemins ou
l'historique, un fondu remplace le vol faute de carte source. Ils respectent
la duree choisie et la reduction des animations.
L'animation est desactivee par defaut et les reglages sont sauvegardes.
Seul le contenu du dossier est anime, une fois le chargement reussi :
l'ancien contenu reste visible avec un indicateur et ses interactions sont
bloquees pendant le chargement. Le retour et la navigation au parent inversent
le glissement ou le zoom. Le chargement initial, les erreurs, l'actualisation,
le tri, la recherche et le changement liste/grille ne declenchent pas de
transition. La reduction des animations du systeme est respectee.
**Automatique** restaure une couleur adaptee au theme,
et **Reinitialiser** restaure tous les reglages.
Tous les reglages sont enregistres automatiquement dans les preferences locales
de l'utilisateur et restaures au demarrage, avant d'afficher l'explorateur.
**Reinitialiser** enregistre aussi les valeurs par defaut. Les erreurs de lecture
ou d'enregistrement sont affichees avec une possibilite de reessayer.

Sous Windows, les raccourcis personnels utilisent les chemins fournis par
`SHGetKnownFolderPath`, y compris lorsque les dossiers sont rediriges vers
OneDrive ou un autre emplacement.

Apres une modification du code natif Windows, arretez puis relancez
l'application avec `flutter run -d windows` : le hot reload ne recharge pas
le code C++.

Un clic droit sur un fichier ou dossier ouvre un popup Flutter contenant les
commandes du Shell Windows. Les sous-menus sont charges a leur ouverture et les
commandes sont executees par Windows. Renommer utilise une boite de dialogue
SurfFile, car cette commande attend normalement une vue de l'Explorateur.

L'option **Afficher le menu Windows** ouvre le menu classique complet, notamment
pour les extensions qui dessinent elles-memes leurs entrees. Ces entrees ne sont
pas reproduites dans le popup Flutter ; les icones natives ne sont pas extraites.
La selection multiple et le menu du fond d'un dossier ne sont pas pris en charge.

Validation : `flutter test` pour les tests Dart et widgets.
Le test non destructif du vrai Shell Windows se lance avec
`flutter run -d windows --profile -t test/native_shell_smoke.dart`.



**SuperLayout** (`lib/widgets/super_layout.dart`) est une disposition en grille
3x3 (Nord-Ouest, Nord, Nord-Est, Ouest, Centre, Est, Sud-Ouest, Sud, Sud-Est)
qui s'edite par clic droit, comme un `SuperContainer`. L'editeur affiche un
apercu et permet de choisir si le Nord, le Sud, l'Est et l'Ouest existent (avec
leur taille) et, pour chaque coin, de le garder en case propre ou de le fusionner
avec l'un de ses deux voisins, jamais les deux (ex. Sud-Ouest avec Ouest ou avec
Sud). Un coin n'existe que si ses deux voisins existent. La structure remonte par
`onChanged` (`SuperLayoutConfig`).

`SuperContainer`, `SuperLayout`, leurs éditeurs et leurs modèles sont regroupés
dans le package Flutter autonome [`super_container_layout`](packages/super_container_layout).
Le point d'entrée est `package:super_container_layout/super_container_layout.dart`.
Le gestionnaire Windows du canal `super_container_layout/window_transparency` est fourni par
`packages/super_container_layout/windows/window_transparency.cpp`. Les runners
de SurfFile et de l'application autonome du package compilent cette source et
appellent `RegisterWindowTransparency` apres l'enregistrement des plugins.
Toute modification de ce code natif necessite une recompilation et un
redemarrage complet de l'application Windows ; le hot reload ne suffit pas.
`SuperApp` y fournit la coquille `MaterialApp` liée aux contrôleurs d'apparence
et de mode édition. Les preferences metier et leur migration appartiennent
uniquement a SurfFile ; les widgets generiques restent utilisables seuls.

Le contenu d'une page est fait de **slots** : une sous-classe de
`SlotImplementation` (`lib/widgets/slot_implementation.dart`, ou `BuilderSlot`
pour un bloc simple) identifiee par son `id`. Le `SuperLayout` les recoit via
`slots` et la config les range dans ses zones par `placements` (ids ordonnes par
zone, empiles de haut en bas). Un cote de `autoSides` prend la taille de son
contenu (hauteur du Nord/Sud, largeur de l'Ouest/Est) au lieu de sa taille
fixe ; le centre recoit le reste.
En mode edition, chaque slot affiche une etiquette (nom, zone et rang) : la
survoler surligne le slot, la glisser sur un autre slot le range avant ou apres
lui, la glisser sur une zone le range en dernier. Le nom d'une zone se survole
et se glisse de la meme facon ; hors du centre, il surligne aussi le centre qui recevra l'echange. Survoler ou glisser une etiquette (slot ou zone) agrandit les etiquettes des slots de sa zone et les noms de toutes les zones. Un clic sur le nom d'une zone la selectionne (cadre epais) ; une disposition imbriquee dans un slot n'affiche ses etiquettes que si la zone qui la contient est selectionnee, ce qui evite de superposer les etiquettes de toutes les dispositions. Un second clic deselectionne. La banniere du mode edition affiche le chemin des dispositions et des zones selectionnees (Page > Centre > Explorateur > Nord), avec le nom court name de chaque SuperLayout. Chaque niveau du chemin est cliquable : un clic sur une zone la deselectionne (comme un clic sur son nom) avec tous les niveaux plus profonds ; un clic sur une disposition ramene la selection a son niveau. Les placements sont sauvegardes avec la
disposition, dans la map `layouts` de l'apparence (ids `explorer`, `explorerMain`,
`explorerSidebar`). L'apparence SurfFile n'expose aucun accesseur type : styles et
dispositions se lisent par id (`style('card')`, `layout('explorer')`,
`styles['selectedCard']`) et se modifient avec `withStyle`/`withLayout` (`null`
supprime une surcharge ; un id par defaut retombe sur `defaultStyles`/
`defaultLayouts`). Les variantes selectionnees heritent de leur style standard
via `variantStyle` et le catalogue `SurfFileAppearanceSlots`.

Le panneau gauche est lui-meme un `SuperLayout` a deux zones : l'espace perso et
les favoris au centre (slot `sidebar-places`), les disques au sud avec une
hauteur automatique plafonnee a la moitie du panneau (slot `sidebar-disks`).

Win + Echap remet toutes les zones et tous les slots par defaut.

En mode edition, le bouton import/export de la banniere ouvre une boite pour echanger le style et la disposition. L'export peut contenir les **styles**, les **dispositions** ou les deux (puces a cocher) ; il se copie dans le presse-papiers ou s'enregistre dans un fichier JSON (surf_file_style.json par defaut). A l'import, le texte est colle ou lu depuis un fichier, la boite indique les groupes qu'il contient et n'applique que ceux qui sont coches ; le resultat est entierement valide avant d'etre applique et sauvegarde. Le format est une enveloppe {format, version, groups, data} (voir lib/services/appearance_transfer.dart) ; un parametrage brut enregistre est aussi accepte.



UI DESIGN
│
├── Réaliste
│   ├── Skeuomorphism
│   └── Neo Skeuomorphism
│
├── Minimaliste
│   ├── Swiss
│   ├── Flat
│   └── Material
│
├── Verre
│   ├── Aero
│   ├── Glassmorphism
│   ├── Liquid Glass
│   ├── Frosted
│   └── Acrylic
│
├── Relief
│   ├── Neumorphism
│   ├── Soft UI
│   └── Claymorphism
│
├── Cartes
│   ├── Card UI
│   ├── Dashboard
│   └── Bento
│
├── Futuriste
│   ├── HUD
│   ├── Cyberpunk
│   ├── Holographic
│   └── AI Native
│
├── Spatial
│   ├── 3D UI
│   ├── Mixed Reality
│   └── Spatial UI
│
└── Artistique
    ├── Brutalism
    ├── Neo Brutalism
    ├── Y2K
    └── Vaporwave