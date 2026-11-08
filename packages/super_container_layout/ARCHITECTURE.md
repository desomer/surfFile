# Architecture et Index des Fichiers — `super_container_layout`

Ce document cartographie l'architecture interne du package `super_container_layout` et dresse l'index exhaustif de ses **167 fichiers Dart** afin de permettre aux agents IA de localiser immédiatement les responsabilités et de modifier le code sans hallucination.

---

## 1. Vue d'ensemble et philosophie

`super_container_layout` est un moteur d'interface graphique modulaire, stylable et éditable à chaud sous Flutter, inspiré de **Flutter GenUI** :
- **Modèle plat par identifiant (`Appearance`)** : Toute l'application est décrite par des dictionnaires immuables indexés par l'ID technique de chaque instance (`components`, `styles`, `behaviors`, `pageCatalog`, `repositories`).
- **Séparation Moteur / Application hôte** : Le package fournit le moteur générique (`SuperApp`, `SuperPage`, `SuperLayout`, `SuperContainer`, `Registry`, `DefaultAppearanceCodec`). Une application hôte comme `SurfFile` enregistre ses composants métier dans `Registry.registerComponent` et compose ses préférences métier via son propre `AppearanceCodec` et `TypedAppearanceScope`.
- **Double mode Exécution / Édition visuelle & IA** : Les mêmes composants s'exécutent sans surcoût en mode normal et exposent des poignées de redimensionnement, du glisser-déposer (modes Zones et Grille), des menus contextuels, un historique undo/redo et un assistant IA (`VibeChatDialog` / `AppearanceTransfer.applyVibe`) lorsque le mode édition est actif.

---

## 2. Flux de données et mécanismes clés

### 2.1. Modèle central `Appearance` et synchronisation `Registry`
1. `Appearance` (et son implémentation standard `DefaultAppearance`) détient l'état persisté complet :
   - `styles` : `Map<String, ContainerStyle>` (surfaces `background`, cartes `Card`, lignes `<listId>:item`, `IterableContent`).
   - `components` : `Map<String, ComponentConfig>` décodés polymorphiquement via `ComponentConfigCatalog` selon le discriminateur `"type"` :
     - `"layout"` → `SuperLayoutConfig`
     - `"native"` → `NativeComponentConfig`
     - `"scaffold"` → `ScaffoldPageConfig`
     - `"value"` → `SuperValueConfig`
     - `"action"` → `SuperActionConfig`
     - `"indicator"` → `SuperIndicatorConfig`
     - `"separator"` → `SuperSeparatorConfig`
     - `"list"` → `SuperListViewConfig`
     - `"tab"` → `SuperTabConfig`
     - `"treeView"` → `SuperTreeViewConfig`
     - `"table"` → `SuperTableConfig`
     - Extensions externes enregistrées via `SuperComponentExtension` / `ComponentConfigCatalog.register` (ex: `"chart"` → `SuperChartConfig` dans le package `super_container_extensions`)
   - `behaviors` : `Map<String, List<ComponentBehavior>>` (navigation `GoToPageAction` au clic, ou `EmitEventAction` au clic/double-clic).
   - `pageCatalog` : `EditorPageCatalog` (liste des pages routées et `homePageId`).
   - `repositories` : `List<JsonRepositoryDocument>` (sources de données JSON réactives).
2. `Registry` maintient un `ValueNotifier<T>` par identifiant de composant/style (`superLayoutConfigById`, `containerStyleById`, `valueConfigById`, `actionConfigById`, `listConfigById`, `tabConfigById`, `chartConfigById`, `treeViewConfigById`, `tableConfigById`, `nativeComponentConfigById`, `scaffoldPageConfigById`).
   - Toute écriture sur un `ValueNotifier` de `Registry` met à jour `ValueNotifier<Appearance>`, ce qui déclenche la sauvegarde asynchrone dans `AppearanceStore`.
   - Inversement, un chargement, un import, un undo/redo ou un patch IA (`applyVibe`) sur `ValueNotifier<Appearance>` resynchronise tous les `ValueNotifier` actifs de `Registry` sans boucle infinie (`_syncing`).

### 2.2. Liaisons JSON réactives (`JsonRepositoryStore` & `JsonListScope`)
- `JsonRepositoryStore` gère plusieurs documents JSON identifiés par un ID hexadécimal de 32 caractères (`JsonRepositoryBinding`).
- `JsonTextBinding` associe un `repositoryId` (ou `""` pour hériter du repository englobant) et un `JsonAttributePath` (ex. `clients[?].nom`).
- Chaque ligne d'un composant de collection (`SuperListView`, `SuperTable`, `SuperTreeView`, `SuperTab` dynamique) enveloppe son sous-arbre dans un `JsonListScope` fournissant l'indice ou le chemin concret de la ligne.
- `JsonListScope.resolveSelected(binding, scope, store)` remplace les jokers `[?]` :
  - d'abord par les indices des `JsonListScope` englobants (de l'extérieur vers l'intérieur) ;
  - puis, pour les `[?]` restants (composants placés hors de la liste), par l'indice de la ligne sélectionnée dans le `JsonArrayBinding` correspondant (**pattern Maître / Détail**).

### 2.3. Surfaces, systèmes de design et états (`ContainerStyle` & `SurfaceStyleStates`)

Les comportements `onTooltip` (`trigger: "hover"`) sont rendus par
`ComponentTooltip`, enveloppe publique commune à tous les types de composants.
`EditorSlot` couvre les composants standard et natifs, pages et collections ;
`SlotImplementation` couvre aussi les slots hôtes et extensions sans code dédié.
La déduplication par ID évite les tooltips multiples des enveloppes imbriquées,
sans masquer ceux des composants enfants distincts. Les slivers utilisent une
ancre box dans l'overlay sans changer leur géométrie.
`JsonStringBinding` partage la lecture réactive de chaînes entre ces info-bulles
et `SurfaceStateBinding` : repository, sélection et contexte de ligne/arbre,
lecture seule, désabonnement et protection contre les réponses obsolètes.
- `SuperContainer` et `StyledSurface` peignent une surface à partir d'un `ContainerStyle` (systèmes `material`, `neumorphism`, `liquidGlass`, remplissage `ContainerFill` uni/dégradé/image/SVG, rayons par coin, bordures par côté, ombres portées et intérieures, halo `NeonStyle`, flou `backdropBlur`, motifs `SurfacePattern` et transformations 2D).
- `SurfaceStyleStates` (ainsi que `SuperValueStates` et `SuperActionStates`) applique dynamiquement des surcharges partielles par groupes de propriétés selon les états actifs :
  - états nommés métier liés au JSON (`states.binding` + `states.named`) ;
  - états d'interaction (`hover`, `selected`) ;
  - états automatiques (`contentHover` via `ContentHoverScope`, `focused`, `disabled`, `readOnly`).

### 2.4. Graphe de pages et opérations d'édition (`EditorPageGraph`)
- `EditorPageGraph` analyse les références entre composants (`placements` de `SuperLayoutConfig`, `NativeComponentConfig`, `ScaffoldPageConfig`, `SuperListViewConfig.template`, `SuperTabConfig`, `SuperTreeViewConfig`, `SuperTableConfig`).
- Il garantit :
  - la **duplication profonde** d'un sous-graphe de composants avec réécriture des IDs selon leur `ComponentDuplicationContract` ;
  - la **suppression propre** d'un slot ou d'une page en nettoyant toutes les configurations et styles orphelins qui ne sont plus référencés ailleurs.

### 2.5. Bus d'evenements de composants

- `SuperEventBus` est injecte dans `SuperApp` et reste possede par l'hote :
  abonnements par ID exact, broadcast asynchrone, sans replay ni singleton.
- `EmitEventAction` est persistee par `BehaviorActionCatalog`. Le contexte
  runtime `BehaviorExecutionData` fournit l'identite de l'instance et un
  instantane JSON ; l'API historique `BehaviorAction.execute(context)` reste
  compatible pour les actions existantes.
- `EditorSlot` delegue les actions d'evenement a `BehaviorEventListener`.
  Celui-ci observe les pointeurs (box/sliver) sans gagner l'arene gestuelle,
  deduplique les slots imbriques equivalents et lit l'apres dans une microtask,
  apres les callbacks natifs synchrones. Les autres actions gardent leur voie
  d'execution historique.
- `SuperValue` fournit explicitement sa valeur runtime locale, y compris dans
  les lignes repetees, sans rechercher un ID dans un sous-arbre. Le payload
  contient `data.previousValue`, `data.value` et `custom` separe ; les collections
  sont copiees et protegees recursivement. Un double-clic conserve les deux clics.

---

## 3. Index complet des 167 fichiers Dart (`packages/super_container_layout/lib/`)

### 3.1. Racine (`lib/` — 4 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `super_container_layout.dart` | Point d'entrée public (barrel file) réexportant les modèles, thèmes, services, composants et éditeurs du package. |
| `super_app.dart` | `SuperApp`, `SuperAppScope` : coquille applicative gérant le routeur `go_router`, `AppearanceStore`, `Registry`, `EditorHistoryController`, `JsonRepositoryStore` et la transparence de fenêtre. |
| `super_page.dart` | `SuperPage` : page standard combinant un `ScaffoldPageLayout` (`root`), un `SuperLayout` principal (`mainLayout`), le fond `background` et la barre flottante d'édition. |
| `main.dart` | Application autonome de démonstration du package `super_container_layout`. |

### 3.2. Intelligence Artificielle (`lib/ai/` — 2 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `ai/call_gemini.dart` | `callGemini` : appel au modèle `gemini-flash-latest` via `google_generative_ai` avec support multimodal des pièces jointes et journalisation de diagnostic. |
| `ai/vibe_chat_attachment.dart` | `VibeChatAttachment` : représentation immuable d'une pièce jointe (image binaire ou fichier texte/JSON) envoyée dans le chat Vibe IA. |

### 3.3. Modèles de données (`lib/models/` — 26 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `models/automatic_state.dart` | `AutomaticState` : énumération des états automatiques (`contentHover`, `focused`, `disabled`, `readOnly`) et encodage de priorité d'état. |
| `models/component_behavior.dart` | `ComponentBehavior`, `BehaviorTrigger`, `BehaviorAction`, `BehaviorExecutionData`, `GoToPageAction`, `EmitEventAction`, `ZoneSizeBindingAction`, `TooltipAction` : navigation et événements (`click`, `doubleClick`), taille de côté liée (`binding`) et info-bulle générique (`onTooltip`, `hover`). |
| `services/events/super_event_bus.dart` | `SuperEventBus`, `SuperComponentEvent` : bus applicatif et snapshots JSON immutables. |
| `widgets/components/behavior_event_listener.dart` | Observation non bloquante des clics et doubles-clics d'evenement, box et sliver. |
| `widgets/components/component_tooltip.dart` | `ComponentTooltip` : info-bulle fixe ou liée pour tout composant identifié, box/sliver, priorité, déduplication et conservation des configurations explicites. |
| `models/component_config.dart` | `ComponentConfig`, `ComponentConfigCodec`, `ComponentConfigCatalog` : classe de base et catalogue de décodage polymorphique des 10 types de composants. |
| `models/component_tag_filter.dart` | `ComponentTagFilter` : filtrage par tags (`include`/`exclude`) des composants autorisés dans une zone ou une région native. |
| `models/editor_page_config.dart` | `EditorPageConfig`, `EditorPageCatalog` : configuration d'une page routée (id, nom, chemin, `scaffoldId`, `layoutId`) et catalogue complet des pages. |
| `models/grid_layout_config.dart` | `GridLayoutConfig`, `GridTrackSize`, `GridPlacement` : configuration du mode Grille CSS-like (pistes `fr`/`px`/`auto`, placement ligne/colonne/span). |
| `models/json_syntax.dart` | `JsonColor`, `JsonComponentType`, `JsonDimension`, `JsonFontWeight`, `JsonSize`, `JsonPlacementEntry` : parseurs et formateurs compacts "AI-friendly". |
| `models/json_text_binding.dart` | `JsonAttributePath`, `JsonPathSegment`, `JsonTextBinding` : analyse syntaxique des chemins JSON (`a.b[0].c`, jokers `[?]`) et liaisons aux repositories. |
| `models/material_icon_catalog.dart` | `MaterialIconCatalog`, `MaterialIconEntry` : catalogue d'icônes Material 3 indexées par identifiant `snake_case` avec recherche floue. |
| `models/native_component_config.dart` | `NativeComponentConfig` : configuration générique des composants natifs (`ApplicationBar`, `BottomAppBar`, `BottomNavigationBar`, `NavigationRail`, `Card`, `Expansible`, `Menu`). |
| `models/native_property_descriptor.dart` | `NativePropertyDescriptor`, `NativeComponentSchema` : descripteurs déclaratifs des propriétés et régions des composants Material natifs. |
| `models/native_shape_config.dart` | `NativeShapeConfig`, `NativeShapeKind` : configuration sérialisable des formes Material (`RoundedRectangleBorder`, `StadiumBorder`, `BeveledRectangleBorder`, `CircleBorder`). |
| `models/registry.dart` | `Registry`, `RegisteredComponent`, `ComponentBuilder`, `ComponentDuplicationContract`, `EditorConfigKind`, `EditorConfigRef` : registre central des composants et synchronisation des `ValueNotifier` avec `Appearance`. |
| `models/scaffold_page_config.dart` | `ScaffoldPageConfig`, `ScaffoldBodyMode` : configuration de la structure `Scaffold` d'une page (`appBar`, `body`, `bottomNavigationBar`, `drawer`, `endDrawer`, `bottomSheet`, mode `standard` ou `customScrollView`). |
| `models/scrollbar_style_config.dart` | `ScrollbarStyleConfig` : personnalisation visuelle des barres de défilement (épaisseur, rayon, visibilité, couleurs). |
| `models/super_action_config.dart` | `SuperActionConfig`, `SuperActionKind`, `SuperActionVariant`, `SuperActionIconPosition`, `SuperActionProperty` : configuration des boutons et actions Material 3 ou surfaciques. |
| `models/super_action_states.dart` | `SuperActionStates`, `SuperActionStateOverride` : surcharges conditionnelles de `SuperActionConfig` par état (`hover`, `selected`, `automatic`, `named`). |
| `models/super_indicator_config.dart` | `SuperIndicatorConfig`, `SuperIndicatorIconPosition`, `SuperIndicatorProperty` : configuration d'un composant indicateur / icône d'état avec libellé et badge optionnels. |
| `models/super_indicator_states.dart` | `IndicatorConfigStates`, `IndicatorConfigOverride`, `IndicatorStateProperty` : surcharges conditionnelles de `SuperIndicatorConfig` par état (`hover`, `selected`, `automatic`, `named`). |
| `models/super_separator_config.dart` | `SuperSeparatorConfig`, `SuperSeparatorKind`, `SuperSeparatorLabelPosition`, `SuperSeparatorProperty` : configuration d'un séparateur (`divider`) ou espaceur (`spacer`) horizontal/vertical avec libellé optionnel. |
| `models/super_separator_states.dart` | `SeparatorConfigStates`, `SeparatorConfigOverride`, `SeparatorStateProperty` : surcharges conditionnelles de `SuperSeparatorConfig` par état (`hover`, `selected`, `automatic`, `named`). |
| `models/super_layout_config.dart` | `SuperLayoutConfig`, `SuperLayoutMode`, `ZoneFlowConfig`, `SlotSizeConstraints`, `SlotDimension` : configuration d'un `SuperLayout` (zones N/S/E/W/Center ou Grille, flux flex, contraintes par slot). |
| `models/super_list_view_config.dart` | `SuperListViewConfig` : configuration d'une liste répétée liée à un tableau JSON avec son `SuperLayoutConfig` de gabarit (`template`). |
| `models/super_tab_config.dart` | `SuperTabConfig`, `SuperTabMode`, `SuperTabIndicatorType` : configuration d'une barre d'onglets `TabBar` + `TabBarView` en mode statique ou dynamique lié au JSON. |
| `models/super_table_config.dart` | `SuperTableConfig`, `SuperTableColumnConfig` : configuration d'un tableau multi-colonnes avec colonnes figées, en-tête, pied et zones par colonne. |
| `models/super_text_field_config.dart` | `SuperTextFieldConfig` : configuration de compatibilité pour les champs de texte éditables. |
| `models/super_tree_view_config.dart` | `SuperTreeViewConfig` : configuration d'un arbre hiérarchique récursif à 2 zones (`header` et `data`). |
| `models/super_value_config.dart` | `SuperValueConfig`, `SuperValueMode`, `SuperValueKind`, `SuperValueProperty` : configuration d'un composant d'affichage ou de saisie (`text`, `checkbox`, `switchControl`). |
| `models/super_value_states.dart` | `SuperValueStates`, `SuperValueStateOverride` : surcharges conditionnelles de `SuperValueConfig` selon les états interactifs ou métier. |

### 3.4. Thème et Styles (`lib/theme/` — 11 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `theme/appearance.dart` | `Appearance`, `AppearanceScope`, `AppearanceServicesScope` : contrat de base de l'apparence globale et `InheritedNotifier` exposant l'apparence et ses services. |
| `theme/appearance_slot.dart` | `AppearanceSlot`, `AppearanceSurfaceRole` : descripteur d'un slot de style nommé dans le catalogue d'une application. |
| `theme/container_fill.dart` | `ContainerFill`, `ContainerFillType` : remplissage d'une surface (couleur unie, dégradé `linear`/`radial`/`sweep`, image/SVG de fond). |
| `theme/container_style.dart` | `ContainerStyle`, `ContainerStyleProperty` : modèle complet de style d'une surface (fond, coins, bordures, ombres, néon, flou, motifs, marges, états, liaisons JSON). |
| `theme/default_appearance.dart` | `DefaultAppearance` : implémentation standard d'`Appearance` ajoutant typographie, dimensions d'éléments et fondu de défilement. |
| `theme/design_system.dart` | `DesignSystem` : énumération des systèmes visuels (`material`, `neumorphism`, `liquidGlass`). |
| `theme/interaction_effect.dart` | `InteractionEffect`, `HoverTint` : effets visuels au clic (`none`, `pressed`, `scale`, `elevation`, `ripple`) et teintes de survol. |
| `theme/neon_style.dart` | `NeonStyle` : paramètres du halo lumineux néon autour d'une surface. |
| `theme/style_extras.dart` | `BorderLineStyle`, `ShadowSpec`, `SurfacePattern`, `SurfaceTransform` : primitives avancées d'ombres, traits de bordure, motifs et transformations 2D. |
| `theme/surface_style_states.dart` | `SurfaceStyleStates`, `SurfaceStyleOverride`, `SurfaceStylePropertyGroup` : surcharges conditionnelles d'un `ContainerStyle` par état. |
| `theme/typed_appearance_scope.dart` | `TypedAppearanceScope<T extends Appearance>` : pont typé raccordant un `ValueNotifier<T>` applicatif au `AppearanceScope` générique avec validation par codec. |

### 3.5. Services (`lib/services/` — 14 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `services/appearance/appearance_codec.dart` | `AppearanceCodec<T>` : contrat de sérialisation, validation, migration et gestion de préférences additionnelles pour un modèle `Appearance`. |
| `services/appearance/appearance_store.dart` | `AppearanceStore` : persistance asynchrone sérialisée dans `SharedPreferences` (clé `appearance.v1`) et création de contrôleurs persistants. |
| `services/appearance/appearance_transfer.dart` | `AppearanceTransfer`, `AppearanceGroup` : import/export JSON par groupes (Styles, Dispositions) et application incrémentale des patches IA (`applyVibe`). |
| `services/appearance/default_appearance_codec.dart` | `DefaultAppearanceCodec` : codec JSON standard (versions 1 à 3) pour `DefaultAppearance`. |
| `services/codegen/dart_code_generator.dart` | Fichier baril réexportant le socle (`core/` : `ComponentDartGenerator`, `DartCodegenContext`, `DartCodeExporter`). |
| `services/codegen/component_dart_generators.dart` | Fichier baril réexportant les générateurs dédiés par composant situés sous `services/codegen/generators/`. |
| `services/codegen/core/component_dart_generator.dart` | `ComponentDartGenerator` : contrat abstrait de générateur de code Dart pour un composant. |
| `services/codegen/core/dart_codegen_context.dart` | `DartCodegenContext` : contexte de génération, résolution des slots, formatage d'expressions Dart (couleurs, polices, styles, etc.). |
| `services/codegen/core/dart_code_exporter.dart` | `DartCodeExporter` : moteur d'export d'une apparence ou fragment en code Dart `_registry.registerComponent(...)`. |
| `services/codegen/generators/` | Dossier dédié contenant chaque classe de génération : `SuperLayoutDartGenerator`, `SuperValueDartGenerator`, `SuperActionDartGenerator`, `SuperIndicatorDartGenerator`, `SuperSeparatorDartGenerator`, `SuperListViewDartGenerator`, `SuperTreeViewDartGenerator`, `SuperTabDartGenerator`, `SuperTableDartGenerator`, `SuperCardDartGenerator`, `SuperIterableContentDartGenerator`, `SuperNativeComponentDartGenerator`, `SuperRendererDartGenerator`. |
| `services/pages/editor_page_graph.dart` | `EditorPageGraph` : graphe de dépendances des composants et styles d'une page (collecte, duplication profonde, nettoyage d'orphelins à la suppression). |
| `services/pages/editor_page_router.dart` | `EditorPageRouter`, `buildEditorGoRouter` : génération dynamique des routes `GoRouter` à partir de `EditorPageCatalog`. |
| `services/repositories/json_list_scope.dart` | `JsonListScope`, `ResolvedJsonBinding` : `InheritedWidget` de contexte de ligne pour les listes/tables/arbres et résolution des jokers `[?]`. |
| `services/repositories/json_repository_binding.dart` | `JsonRepositoryBinding`, `JsonArrayBinding`, `JsonAttributeBinding` : liaisons réactives `ValueNotifier` sur un document JSON en mémoire. |
| `services/repositories/json_repository_scope.dart` | `JsonRepositoryScope` : `InheritedNotifier` exposant le `JsonRepositoryStore` à tout l'arbre de widgets. |
| `services/repositories/json_repository_store.dart` | `JsonRepositoryStore`, `JsonRepositoryDocument` : magasin multi-documents JSON réactif avec validation et extraction de chemins. |
| `services/repositories/json_text_controller_binding.dart` | `JsonTextControllerBinding` : synchronisation bidirectionnelle sans boucle entre un `TextEditingController` et un attribut JSON. |
| `services/states/content_hover_scope.dart` | `ContentHoverScope` : propagation de l'état de survol d'un conteneur parent (`IterableContent`) vers ses composants enfants (`AutomaticState.contentHover`). |
| `services/states/surface_state_binding.dart` | `SurfaceStateBinding` : adaptation du lecteur partagé `JsonStringBinding` pour l'état métier nommé (`states.binding`). |
| `services/repositories/json_string_binding.dart` | `JsonStringBinding` : lecture seule réactive d'une chaîne JSON, contexte de ligne/arbre et sélection maître/détail, diagnostics et gestion du cycle de vie. |
| `services/window/window_transparency.dart` | `WindowTransparency`, `WindowEffectType` : pilotage multi-plateforme des effets de transparence et d'opacité de fenêtre via `flutter_acrylic`. |

### 3.6. Widgets d'apparence et de surfaces (`lib/widgets/appearance/` & `lib/widgets/surfaces/` — 10 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `widgets/appearance/appearance_settings.dart` | `AppearanceSettings`, `showAppearanceSettingsDialog` : boîte de dialogue complète de configuration du thème, des polices, de la transparence et des slots de style. |
| `widgets/appearance/appearance_style_section.dart` | `AppearanceStyleSection` : section réutilisable d'édition des slots de style avec aperçu en direct. |
| `widgets/appearance/appearance_toolbar.dart` | `AppearanceToolbar` : barre d'outils flottante et déplaçable donnant accès au thème, au mode édition, à l'historique undo/redo, aux pages, aux repositories et au chat Vibe IA. |
| `widgets/appearance/appearance_transfer_dialog.dart` | `AppearanceTransferDialog` : dialogue d'import/export JSON des styles et dispositions (presse-papiers ou fichier). |
| `widgets/surfaces/interaction_effect_box.dart` | `InteractionEffectBox` : wrapper animant les effets d'interaction au survol et au clic (`pressed`, `scale`, `elevation`, `ripple`). |
| `widgets/surfaces/neon_surface.dart` | `NeonSurface` : rendu du halo lumineux néon externe autour d'un conteneur. |
| `widgets/surfaces/scroll_edge_fade.dart` | `ScrollEdgeFade` : masque de fondu progressif en haut et en bas d'une zone défilante. |
| `widgets/surfaces/styled_surface.dart` | `StyledSurface` : application complète d'un `ContainerStyle` (dégradés, images, flou `liquidGlass`, ombres neumorphiques, bordures, motifs, transformations). |
| `widgets/surfaces/super_container.dart` | `SuperContainer` : conteneur de haut niveau résolvant son `ContainerStyle` depuis `AppearanceScope`, ses états (`SurfaceStyleStates`) et ses liaisons JSON. |
| `widgets/surfaces/surface_painters.dart` | `DashedBorderPainter`, `InnerShadowPainter`, `SurfacePatternPainter` : `CustomPainter` pour bordures tiretées/pointillées, ombres intérieures et motifs (`grain`, `lines`, `dots`). |

### 3.7. Widgets de composants (`lib/widgets/components/` — 41 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `widgets/components/component_common.dart` | Utilitaires partagés entre composants (résolution de comportements `ComponentBehavior`, exécution de `GoToPageAction`, curseurs). |
| `widgets/components/super_component.dart` | Contrat type `SuperComponent<C>` (`id`, `config`, `behaviours`), bases `SuperStatefulComponent` et `SuperStatelessComponent`. Les comportements explicites remplacent ceux de l'apparence pour l'instance, sans les persister ; `null` conserve l'apparence. |
| `widgets/components/super_action.dart` | `SuperAction` : bouton/action configurable (variantes Material 3 `filled`/`tonal`/`elevated`/`outlined`/`text`/`icon` ou `surface`, états, liaisons JSON et comportements). |
| `widgets/components/super_indicator.dart` | `SuperIndicator` : indicateur / icône d'état configurable avec libellé et badge optionnels, états standards/nommés (`SurfaceStateBinding`) et `propertyBindings`. |
| `widgets/components/super_separator.dart` | `SuperSeparator` : séparateur (`divider`) ou espaceur (`spacer`) horizontal/vertical avec libellé optionnel, style de trait (`solid`/`dashed`/`dotted`), états et liaisons JSON. |
| `widgets/components/super_list_view.dart` | `SuperListView` : liste dynamique liée à un tableau JSON, répétant un gabarit `IterableContent` par ligne avec ajout/suppression et sélection. |
| `widgets/components/super_tab.dart` | `SuperTab` : composant d'onglets (`TabBar` + `TabBarView`) en mode statique (vues par onglet) ou dynamique (lié à un tableau JSON). |
| `widgets/components/super_table.dart` | `SuperTable` : tableau multi-colonnes avec colonnes figées à gauche, en-tête, pied, redimensionnement de colonnes et `JsonListScope` par ligne. |
| `widgets/components/super_text_field.dart` | `SuperTextField` : champ de saisie stylable lié à `SuperTextFieldConfig`. |
| `widgets/components/super_tree_view.dart` | `SuperTreeView` : arbre hiérarchique récursif à 2 zones (`header` et `data`) lié à un repository JSON. |
| `widgets/components/super_value.dart` | `SuperValue` : composant d'affichage ou de saisie (`text`, `checkbox`, `switchControl`) avec liaison bidirectionnelle `JsonTextBinding` et états. |
| `widgets/components/internal_widget/array/cw_table_layout.dart` | `CwTableLayout` : moteur de disposition interne synchronisant le défilement horizontal et vertical des colonnes figées et défilantes de `SuperTable`. |
| `widgets/components/internal_widget/array/cw_table_row.dart` | `CwTableRow` : rendu synchronisé d'une ligne de `SuperTable` (états de survol/sélection et `ContainerStyle` partagés entre colonnes figées et corps). |
| `widgets/components/internal_widget/treeview/tree_view.dart` | Primitives internes d'aplatissement, d'expansion/repli et de peinture des connecteurs hiérarchiques pour `SuperTreeView`. |
| `widgets/components/internal_widget/widget_breadcrumb.dart` | Fil d'Ariane interne pour la navigation hiérarchique dans les composants/éditeurs. |
| `widgets/components/internal_widget/widget_overflow.dart` | Gestion du débordement gracieux de widgets dans les barres et zones contraintes. |
| `widgets/components/native/native_component_common.dart` | `NativePreferredSizeWidget`, helpers de construction des régions et slots pour les composants Material natifs. |
| `widgets/components/native/scaffold_page_layout.dart` | `ScaffoldPageLayout` : assemblage d'un `Scaffold` Flutter (ou `CustomScrollView` avec `SliverAppBar`) piloté par `ScaffoldPageConfig` et `NativeComponentConfig`. |
| `widgets/components/native/super_app_bar.dart` | `SuperAppBar` : barre d'application Material 3 (`AppBar` / `SliverAppBar`) à régions éditables (`leading`, `title`, `actions`, `bottom`, `flexibleSpace`). |
| `widgets/components/native/super_bottom_app_bar.dart` | `SuperBottomAppBar` : `BottomAppBar` éditable à 3 régions (`left`, `center`, `right`). |
| `widgets/components/native/super_bottom_navigation_bar.dart` | `SuperBottomNavigationBar` : `BottomNavigationBar` dont les destinations sont des composants `SuperAction`. |
| `widgets/components/native/super_expansible.dart` | `SuperExpansible` : panneau dépliable (`Expansible`) à 2 régions (`header`, `body`) avec liaison booléenne JSON optionnelle. |
| `widgets/components/native/super_menu_anchor.dart` | `SuperMenuAnchor` : menu popup (`MenuAnchor`) à 2 régions (`header` ancre et `body` contenu du menu). |
| `widgets/components/native/super_navigation_rail.dart` | `SuperNavigationRail` : `NavigationRail` vertical à 3 régions (`leading`, `destinations`, `trailing`). |
| `widgets/components/super_layout/super_layout.dart` | `SuperLayout`, `SuperLayoutSlot` : widget principal de disposition modulaire en 5 zones cardinales (`north`, `south`, `west`, `east`, `center`) ou en grille. |
| `widgets/components/super_layout/registered_super_layout.dart` | `RegisteredSuperLayout` : connecte un `SuperLayout` au `Registry` et à `AppearanceScope` par son identifiant. |
| `widgets/components/super_layout/iterable_content.dart` | `IterableContent` : composant combinant une surface stylisée (`EditableSurface`) et un `SuperLayout` interne sous un même concept de ligne/carte répétable. |
| `widgets/components/super_layout/layout.dart` | Logique de résolution des slots et de construction de l'arbre d'un `SuperLayout`. |
| `widgets/components/super_layout/layout_view.dart` | `SuperLayoutView` : vue d'exécution/édition assemblant les zones cardinales ou la grille, les poignées de redimensionnement et les cibles de dépôt. |
| `widgets/components/super_layout/zone_layout.dart` | Algorithme de disposition des 5 zones cardinales (`north`, `south`, `west`, `east`, `center`) et calcul des tailles effectives. |
| `widgets/components/super_layout/grid_view.dart` | Rendu et glisser-déposer de `SuperLayout` lorsqu'il est configuré en mode Grille (`SuperLayoutMode.grid`). |
| `widgets/components/super_layout/grid_slot_editor.dart` | Contrôles d'édition du placement en grille (ligne, colonne, rowSpan, colSpan) d'un slot. |
| `widgets/components/super_layout/layout_editor.dart` | Actions de modification structurelle d'un `SuperLayoutConfig` (déplacement, échange, redimensionnement, ajout/suppression de slots). |
| `widgets/components/super_layout/layout_dialogs.dart` | Boîtes de dialogue de configuration d'une zone ou d'un `SuperLayout` (axes, flux `ZoneFlowConfig`, grille, barres de défilement). |
| `widgets/components/super_layout/layout_selection.dart` | `LayoutSelectionController`, `LayoutSelectionScope` : gestionnaire de sélection hiérarchique progressive (clic zone → double-clic enfant) en mode édition. |
| `widgets/components/super_layout/layout_slots.dart` | Modèles internes et helpers de résolution des slots placés dans un `SuperLayout`. |
| `widgets/components/super_layout/layout_reset_shortcut.dart` | Raccourci clavier et action de réinitialisation d'une disposition à ses valeurs par défaut. |
| `widgets/components/super_layout/label_scope.dart` | `LabelScope` : visibilité et survol des badges/labels de zones et de composants en mode édition. |
| `widgets/components/super_layout/slot_implementation.dart` | `SlotImplementation`, `BuilderSlot`, `SlotFactory`, `ZoneScrollableViewport` : abstraction d'un slot plaçable et instanciation depuis le `Registry`. |
| `widgets/components/super_layout/slot_size_editor.dart` | Éditeur de taille préférée et de contraintes (`SlotSizeConstraints`) d'un slot dans un `SuperLayout`. |
| `widgets/components/super_layout/zone_axis_button.dart` | Bouton rapide de bascule d'axe (`horizontal` / `vertical`) et de paramètres de flux sur une zone en mode édition. |
| `widgets/components/super_layout/zone_interactions.dart` | Cibles de glisser-déposer (`DragTarget`) et retour visuel lors du déplacement de slots ou de zones. |
| `widgets/components/super_layout/zone_resize_handle.dart` | Poignée de redimensionnement interactif entre les zones cardinales (`north`, `south`, `west`, `east`) et `center`. |

### 3.8. Widgets du mode Édition (`lib/widgets/editing/` — 59 fichiers)
| Fichier | Rôle et classes principales |
| :--- | :--- |
| `widgets/editing/addition/component_add_wizard.dart` | `ComponentAddWizard` : assistant guidé d'ajout d'un composant dans une zone ou une région native avec aperçu et configuration initiale. |
| `widgets/editing/addition/component_add_configurators.dart` | Catalogue des `ComponentAddConfigurator` branchés sur chaque composant de `Registry.bootstrap()`. |
| `widgets/editing/addition/contextual_add.dart` | Menu et logique d'ajout contextuel rapide (`+`) sur une zone, une région native ou un conteneur vide. |
| `widgets/editing/addition/insertion_plan.dart` | `InsertionPlan` : planification atomique de l'insertion d'un composant et de ses sous-configurations initiales dans `Appearance`. |
| `widgets/editing/addition/forms/add_form_common.dart` | Widgets de formulaire partagés entre les assistants d'ajout de composants. |
| `widgets/editing/addition/forms/container_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `Card` ou `IterableContent`. |
| `widgets/editing/addition/forms/expansible_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperExpansible`. |
| `widgets/editing/addition/forms/list_view_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperListView`. |
| `widgets/editing/addition/forms/menu_anchor_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperMenuAnchor`. |
| `widgets/editing/addition/forms/super_action_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperAction`. |
| `widgets/editing/addition/forms/super_indicator_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperIndicator`. |
| `widgets/editing/addition/forms/super_separator_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperSeparator`. |
| `widgets/editing/addition/forms/super_value_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperValue`. |
| `widgets/editing/addition/forms/tab_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperTab`. |
| `widgets/editing/addition/forms/table_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperTable`. |
| `widgets/editing/addition/forms/tree_view_add_form.dart` | Formulaire de configuration initiale lors de l'ajout d'un `SuperTreeView`. |
| `widgets/editing/ai/vibe_chat_dialog.dart` | `VibeChatDialog` : panneau/dialogue de chat IA ("Vibe") construisant le prompt avec `SCREEN_JSON_AI_GUIDE.md`, l'export JSON courant (ou ciblé par `VibeChatScope`) et appliquant la réponse via `AppearanceTransfer.applyVibe`. |
| `widgets/editing/behaviors/component_behavior_editor.dart` | `ComponentBehaviorWizard` : assistant de comportements, navigation, événements, taille liée et info-bulle fixe ou liée au repository. |
| `widgets/editing/components/native_component_editor.dart` | Point d'entrée public de l'éditeur générique des propriétés et régions d'un composant Material natif (`NativeComponentConfig`). |
| `widgets/editing/components/native_editor/native_region_slot.dart` | Contrats de région (`NativeRegion`) et slots d'adaptation de taille préférée (`NativePreferredSizeWidget`, `NativeWidgetSlot`, `NativeInstanceSlot`). |
| `widgets/editing/components/native_editor/native_property_control.dart` | Contrôles d'édition de propriétés déclaratives (`buildNativePropertyControl`) et délégué de flux (`NativeRegionFlowDimensionDelegate`). |
| `widgets/editing/components/native_editor/native_editor_selection.dart` | Extension `NativeComponentEditorSelection` : enregistrement `LayoutSelection`, sélection des régions/slots, actions d'axe et infobulles. |
| `widgets/editing/components/native_editor/native_editor_dialogs.dart` | Extension `NativeComponentEditorDialogs` : boîte de dialogue `configure()` et ouverture de l'éditeur de flux de région. |
| `widgets/editing/components/native_editor/native_editor_slots.dart` | Extension `NativeComponentEditorSlots` : résolution des slots (`slotsFor`), renommage d'instance et dimensionnement (`preferredSizeFor`, `_editSize`). |
| `widgets/editing/components/native_editor/native_editor_addition.dart` | Extension `NativeComponentEditorAddition` : assistant d'ajout (`add`) et insertion contextuelle autour d'un slot ou dans une région. |
| `widgets/editing/components/native_editor/native_editor_interactions.dart` | Extension `NativeComponentEditorInteractions` : glisser-déposer de slots (`_moveSlot`) et actions d'encapsulation (`wrapActionsForSlot`, `wrapActionsForRegion`). |
| `widgets/editing/components/native_editor/native_editor_regions.dart` | Extension `NativeComponentEditorRegions` : rendu des slots, régions Box/Sliver et cible de dépôt/overlays partagés (`_buildRegionZoneTarget`). |
| `widgets/editing/components/native_shape_editor.dart` | Éditeur visuel de forme Material (`NativeShapeConfig`). |
| `widgets/editing/components/shared/component_state_editor_host.dart` | Hôte générique d'édition multi-états (`ComponentStateEditorHost`, `ComponentStateAdapter`, `showStatefulComponentEditorDialog`). |
| `widgets/editing/components/shared/editor_color_fields.dart` | Contrôles de couleurs, liaisons par propriété et champs de boîte partagés (`BoundHexColorField`, `ThemeResetColorTile`, `EditablePropertyBindingScope`, `ComponentEditorPreviewCard`, `buildComponentBoxDimensionFields`). |
| `widgets/editing/components/shared/component_typography_controls.dart` | Contrôles réutilisables de typographie et d'alignement (`ComponentFontFamilyField`, `ComponentFontWeightField`, `ComponentItalicSegmentField`, `ComponentTextAlignSegmentField`). |
| `widgets/editing/components/shared/surface_quick_controls_section.dart` | Section réutilisable des effets et réglages rapides de surface (`buildSurfaceQuickControlsSection`). |
| `widgets/editing/components/shared/collection_editor_controls.dart` | Contrôles de liaison de collection JSON et éditeur de colonnes de table (`CollectionRepositorySourceFields`, `SuperTableColumnsEditor`, `verifyCollectionBindingTarget`). |
| `widgets/editing/components/super_action_editor.dart` | Fenêtre d'édition complète d'un `SuperAction` (contenu, icône, couleurs, typographie, surface, états, liaisons JSON, comportements). |
| `widgets/editing/components/super_indicator_editor.dart` | Fenêtre d'édition complète d'un `SuperIndicator` (icône, libellé, badge/surface, typographie, états standards/nommés, liaisons JSON). |
| `widgets/editing/components/super_separator_editor.dart` | Fenêtre d'édition complète d'un `SuperSeparator` (type divider/spacer, orientation, style de trait, libellé, états, liaisons JSON). |
| `widgets/editing/components/super_list_view_editor.dart` | Fenêtre d'édition d'un `SuperListView` (liaison JSON, dimensions de ligne, ajout/suppression, message vide). |
| `widgets/editing/components/super_tab_editor.dart` | Fenêtre d'édition d'un `SuperTab` (mode statique/dynamique, onglets, indicateur, style de barre, liaison JSON). |
| `widgets/editing/components/super_table_editor.dart` | Fenêtre d'édition d'un `SuperTable` (colonnes, largeurs/fillPercent, colonnes figées, en-tête/pied, liaison JSON). |
| `widgets/editing/components/super_text_field_settings.dart` | Dialogue de paramètres d'un `SuperTextField`. |
| `widgets/editing/components/super_tree_view_editor.dart` | Fenêtre d'édition d'un `SuperTreeView` (liaison JSON, `childrenKey`, largeur `header`, indentation, connecteurs). |
| `widgets/editing/components/super_value_editor.dart` | Fenêtre d'édition complète d'un `SuperValue` (mode affichage/saisie, type texte/checkbox/switch, typographie, états, liaison JSON). |
| `widgets/editing/dialogs/editor_dialog.dart` | `showEditorDialog` : affichage de boîtes de dialogue d'édition ancrées et déplaçables sans masquer la cible éditée. |
| `widgets/editing/dialogs/editor_dialog_header.dart` | `EditorDialogHeader` : barre de titre standard des dialogues d'édition avec glisser-déposer et bouton de fermeture. |
| `widgets/editing/dialogs/editor_tabbed_wizard.dart` | `EditorTabbedWizard` : structure à onglets réutilisable pour les fenêtres d'édition complexes. |
| `widgets/editing/dialogs/editor_target_selector.dart` | Sélecteur permettant de basculer entre les cibles parentes/enfants lors de l'ouverture d'un éditeur. |
| `widgets/editing/dialogs/super_value_json_extract_dialog.dart` | Assistant d'extraction d'une valeur statique vers un attribut de repository JSON. |
| `widgets/editing/history/editor_history.dart` | `EditorHistoryController`, `EditorHistoryScope` : pile Undo / Redo capturant les instantanés d'`Appearance` et des repositories JSON. |
| `widgets/editing/icons/material_icon_picker.dart` | `MaterialIconPicker` : sélecteur visuel d'icônes Material avec recherche instantanée dans `MaterialIconCatalog`. |
| `widgets/editing/overlay/editor_overlay.dart` | Superposition globale du mode édition coordonnant les cadres de sélection, les badges et les poignées. |
| `widgets/editing/overlay/editor_resize_handle.dart` | Poignées carrées de 8 px (zone de saisie de 32 px) aux coins et côtés pour redimensionner un slot à la souris. |
| `widgets/editing/overlay/editor_zone_badge.dart` | `EditorZoneBadge`, `EditorZoneHighlight`, `EditorSelectionBorder` : badges déplaçables et contours de survol/sélection des zones et composants. |
| `widgets/editing/overlay/editor_zoom.dart` | Contrôleur et raccourcis de zoom/panoramique du canevas en mode édition. |
| `widgets/editing/overlay/style_edit_banner.dart` | `StyleEditBanner` : bannière supérieure du mode édition hébergeant les contrôles rapides et le panneau latéral Vibe IA. |
| `widgets/editing/pages/editor_page_manager.dart` | Gestionnaire des pages de l'application (`EditorPageCatalog` : création, renommage, duplication, suppression, page d'accueil). |
| `widgets/editing/repositories/json_repository_manager.dart` | Éditeur et gestionnaire des documents `JsonRepositoryDocument` (import/export JSON, édition de schéma/données). |
| `widgets/editing/repositories/repository_binding_fields.dart` | Champs d'interface réutilisables pour sélectionner un repository et un chemin `JsonTextBinding` avec autocomplétion. |
| `widgets/editing/slots/editable_single_child.dart` | Conteneur éditable monoenfant (utilisé notamment pour la région `child` d'une `Card`). |
| `widgets/editing/slots/editable_surface.dart` | `EditableSurface` : surface interactive en mode édition permettant d'éditer son `ContainerStyle`, son contenu et ses états. |
| `widgets/editing/slots/editor_context_menu.dart` | `EditorContextMenu`, `VibeChatScope` : modèles et `InheritedWidget` du menu contextuel riche du mode édition (`EditorSlotAction`, `EditorContextMenuEntry`, pastille de couleur). |
| `widgets/editing/slots/editor_context_menu_dialog.dart` | `part of 'editor_slot.dart'` : route popup, boîte de dialogue flottante/déplaçable et délégué de positionnement du menu contextuel. |
| `widgets/editing/slots/editor_selection_outline.dart` | `part of 'editor_selection_region.dart'` : animation et peintre `EditorSelectionOutline` du cadre de sélection et de survol. |
| `widgets/editing/slots/editor_selection_region.dart` | `EditorSelectionRegion` : détection des clics/doubles-clics et sélection hiérarchique progressive d'un composant ou d'une zone. |
| `widgets/editing/slots/editor_slot.dart` | `EditorSlot`, `EditorSlotState`, `StyleEditScope` : wrapper d'édition universel autour d'un slot de composant (cycle de vie, survol/highlight, rendu Box/Sliver). |
| `widgets/editing/slots/editor_slot_export.dart` | `part of 'editor_slot.dart'` (`EditorSlotExportExtension`) : inspection du graphe vivant des composants et export JSON/Dart ou ouverture IA ciblée. |
| `widgets/editing/slots/editor_slot_menu.dart` | `part of 'editor_slot.dart'` (`EditorSlotMenuExtension`) : construction et ouverture du menu contextuel hiérarchique (`openMenu`, badges, indicateurs, actions rapides). |
| `widgets/editing/slots/editor_slot_targets.dart` | `part of 'editor_slot.dart'` (`EditorSlotTargetsExtension`) : renommage, résolution contextuelle et collecte des cibles (`editableChain`, insertions, comportements, données). |
| `widgets/editing/slots/provided_slot_scope.dart` | `ProvidedSlotScope` : portée transmettant les métadonnées et actions du slot parent aux sous-composants. |
| `widgets/editing/slots/sliver_pointer_region.dart` | `part of 'editor_selection_region.dart'` : `SliverSlotScope`, `SliverPointerRegion` et son `RenderProxySliver` pour le survol et la peinture d'enfants Sliver. |
| `widgets/editing/slots/slot_removal.dart` | Logique de suppression sécurisée d'un slot et nettoyage de ses configurations via `EditorPageGraph`. |
| `widgets/editing/slots/slot_size_editor.dart` | `SlotSizeDimensionDelegate`, `showSlotSizeEditor` : dialogue et contrôles d'édition fine des contraintes `SlotSizeConstraints` d'un slot. |
| `widgets/editing/slots/slot_size_preview.dart` | `part of 'slot_size_editor.dart'` : aperçu géométrique interactif (Layout / Zone / Slot) dans l'éditeur de taille de slot. |
| `widgets/editing/slots/slot_wrapping.dart` | Actions permettant d'envelopper un composant existant dans une `Card` ou un `SuperLayout`, ou de le désenvelopper. |
| `widgets/editing/states/editor_state_controls.dart` | Contrôles génériques d'édition des surcharges d'états (`hover`, `selected`, `automatic`, états métier `named`). |
| `widgets/editing/styles/container_style_dialog.dart` | Ouverture de l'éditeur de `ContainerStyle` dans une fenêtre de dialogue flottante. |
| `widgets/editing/styles/container_style_editor.dart` | `ContainerStyleEditor` : éditeur complet d'un `ContainerStyle` (système de design, fond, dégradé, image, coins, bordures, ombres, néon, états). |
| `widgets/editing/styles/independent_spacing_editor.dart` | Éditeur de marges/paddings/rayons/bordures uniformes ou indépendants par côté/coin. |
| `widgets/editing/styles/scrollbar_style_editor.dart` | Éditeur visuel d'un `ScrollbarStyleConfig`. |
| `widgets/editing/styles/style_editor_panel.dart` | Panneau modulaire d'édition des sections d'un style de surface. |
| `widgets/editing/styles/style_extras_controls.dart` | Contrôles d'édition des effets avancés (`ShadowSpec`, `InnerShadow`, `NeonStyle`, `SurfacePattern`, `SurfaceTransform`, `backdropBlur`). |
| `widgets/editing/styles/surface_state_controls.dart` | Interface de sélection et de surcharge des propriétés de `SurfaceStyleStates`. |

---

## 4. Table de routage rapide pour l'IA : Où intervenir ?

| Besoin | Fichiers à consulter / modifier |
| :--- | :--- |
| **Ajouter ou modifier un composant du catalogue** | `lib/models/<comp>_config.dart` → `lib/models/component_config.dart` → `lib/models/json_syntax.dart` → `lib/theme/appearance.dart` & `default_appearance.dart` → `lib/models/registry.dart` → `lib/services/pages/editor_page_graph.dart` → `lib/widgets/components/<comp>.dart` → `lib/widgets/editing/components/<comp>_editor.dart` → `SCREEN_JSON_AI_GUIDE.md` |
| **Ajouter une propriété visuelle sur les cartes/surfaces** | `lib/theme/container_style.dart` (et `container_fill.dart` / `style_extras.dart`) → `lib/theme/surface_style_states.dart` → `lib/widgets/surfaces/styled_surface.dart` → `lib/widgets/editing/styles/container_style_editor.dart` → `SCREEN_JSON_AI_GUIDE.md` |
| **Modifier la résolution des liaisons JSON ou `[?]`** | `lib/models/json_text_binding.dart` → `lib/services/repositories/json_list_scope.dart` → `lib/services/repositories/json_repository_binding.dart` |
| **Modifier l'import/export JSON ou l'application d'un patch Vibe IA** | `lib/services/appearance/default_appearance_codec.dart` → `lib/services/appearance/appearance_transfer.dart` → `lib/widgets/editing/ai/vibe_chat_dialog.dart` |
| **Modifier la sélection, le glisser-déposer ou le redimensionnement en édition** | `lib/widgets/components/super_layout/layout_selection.dart` → `lib/widgets/components/super_layout/layout_view.dart` → `lib/widgets/editing/slots/editor_slot.dart` → `lib/widgets/editing/overlay/editor_resize_handle.dart` |
