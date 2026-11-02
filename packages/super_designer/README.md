# super_designer

Application autonome d'édition visuelle et IA combinant le moteur [`super_container_layout`](../super_container_layout) et le package d'extensions de composants [`super_container_extensions`](../super_container_extensions) (dont `SuperChart`).

## Lancement

```powershell
cd packages/super_designer
flutter run -d windows
```

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
