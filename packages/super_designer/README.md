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

L'evenement fournit `componentId`, `trigger`, `data.previousValue`,
`data.value` et un objet `custom` configurable. Le double-clic conserve
les deux clics simples s'ils sont configures. Le bus et les abonnements
sont liberes dans `dispose`.
