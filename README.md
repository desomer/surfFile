# SurfFile

Un explorateur de fichiers de bureau Flutter.

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
Cette fonctionnalite utilise les API Windows et necessite une reconstruction
complete apres sa premiere installation, pas seulement un rechargement a chaud.

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
