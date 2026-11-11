# super_designer

Application autonome d'édition visuelle et IA combinant le moteur [`super_container_layout`](../super_container_layout) et le package d'extensions de composants [`super_container_extensions`](../super_container_extensions) (dont `SuperChart`).

## Lancement

```powershell
cd packages/super_designer
flutter run -d windows
```

La bannière du mode édition apparaît initialement en bas de la page et reste
déplaçable à la souris. Le chat Vibe et le menu du chemin restent accessibles
lorsqu'ils sont ouverts.

## Repository de SuperDesigner

L'application charge automatiquement son repository au demarrage et enregistre
ses modifications dans
`%USERPROFILE%\.super_container_layout\repositories\registered\0123456789abcdef0123456789abcdef.json`
sous Windows (`$HOME/.super_container_layout/repositories/registered/` ailleurs).
Une erreur de chargement est affichee sans ecraser le fichier existant. Les
identifiants et les champs saisis des nœuds sont conserves lors de la
restauration et des modifications ulterieures du YAML.

Le `main` active la persistance avec `SuperDesignerApp(persistRepository: true)`.
Un hote peut fournir `repositoryDirectory` pour choisir un autre dossier ; sans
activation explicite, `SuperDesignerApp` conserve son comportement en memoire.
Les methodes `saveRepository` et `loadRepository` du store restent disponibles
pour un enregistrement ou un rechargement manuel, ainsi que les boutons
**Enregistrer** et **Recharger** du gestionnaire Repository. Lors d'une demande
normale de fermeture, l'application attend les liaisons, la validation et la
sauvegarde ; une erreur de sauvegarde est affichee et annule la fermeture.
Les donnees d'une ancienne session uniquement en memoire ne sont pas importees
automatiquement : les copier avant de redemarrer cette session.

## Evenements internes

Le widget racine de [main.dart](lib/main.dart) fournit un `SuperEventBus` a
`SuperApp` et ecoute l'ID `node.click`. Le `SuperValue` `tree-node-name`
declare son behaviour clic directement dans son attribut `behaviours: [...]`
dans le main. Il emet cet evenement sur ce bus, sans ajout ni migration dans
l'apparence. Cette liste explicite est prioritaire sur les behaviours sauvegardes.

Chaque `node.click` bascule l'attribut repository `estSize` entre `300` et `0`.
Un `ZoneSizeBindingAction` declare dans les `behaviours` du layout lie la taille
de sa zone est a cet attribut : le panneau `global-node-properties` se ferme
et se rouvre avec l'animation du behaviour (250 ms par defaut). Sa largeur
initiale est de 300 px. Les evenements sont traites dans l'ordre.

L'evenement fournit `componentId`, `trigger`, `data.previousValue`,
`data.value` et un objet `custom` configurable. Le double-clic conserve
les deux clics simples s'ils sont configures. Le bus et les abonnements
sont liberes dans `dispose`.
