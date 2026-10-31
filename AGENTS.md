# Instructions pour les agents IA — SurfFile & `super_container_layout`

Ce dépôt est un monorepo Flutter comprenant l'application de bureau **SurfFile** et le package modulaire d'interface **super_container_layout** (moteur d'interfaces dynamiques et d'édition visuelle/IA inspiré de Flutter GenUI).

---

## 1. Documentation de référence à consulter en priorité

Avant toute modification, consultez les guides spécialisés du dépôt :
- [`packages/super_container_layout/ARCHITECTURE.md`](packages/super_container_layout/ARCHITECTURE.md) : Cartographie des couches, flux de données (`Appearance` ↔ `Registry`, `JsonListScope`, `EditorPageGraph`, `applyVibe`) et **index complet des 167 fichiers Dart** de `super_container_layout`.
- [`packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md`](packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md) : Spécification complète du format JSON plat GenUI (`components`, `styles`, `behaviors`, `pageCatalog`) utilisé pour la persistance et l'assistant IA intégré (Vibe Chat).
- [`packages/super_container_layout/README.md`](packages/super_container_layout/README.md) : Documentation fonctionnelle et exemples d'utilisation des widgets, éditeurs et services de `super_container_layout`.
- [`README.md`](README.md) : Intégration de `super_container_layout` dans l'application hôte `SurfFile`.

---

## 2. Structure du dépôt

- **`lib/` (Application `surf_file`)** : Explorateur de fichiers de bureau Windows (vues liste/grille/colonnes/treemap, jauges de disque, aperçus texte/image/vidéo, intégration shell Windows) construit au-dessus de `super_container_layout`.
- **`packages/super_container_layout/lib/` (Package `super_container_layout`)** :
  - `models/` : Modèles immuables de configuration (`ComponentConfig`, `SuperLayoutConfig`, `NativeComponentConfig`, `ScaffoldPageConfig`, `SuperValueConfig`, `SuperActionConfig`, `SuperListViewConfig`, `SuperTabConfig`, `SuperTableConfig`, `SuperTreeViewConfig`, `SuperChartConfig`), `Registry`, `ComponentBehavior`, `JsonTextBinding`, `JsonSyntax`.
  - `theme/` : `Appearance`, `DefaultAppearance`, `ContainerStyle`, `ContainerFill`, `SurfaceStyleStates`, `DesignSystem`, `NeonStyle`, `StyleExtras`, `TypedAppearanceScope`.
  - `services/` : Persistance et codecs (`AppearanceStore`, `AppearanceCodec`, `DefaultAppearanceCodec`, `AppearanceTransfer`), routage et graphe de pages (`EditorPageRouter`, `EditorPageGraph`), repositories JSON (`JsonRepositoryStore`, `JsonRepositoryBinding`, `JsonListScope`), états automatiques (`SurfaceStateBinding`, `ContentHoverScope`).
  - `widgets/surfaces/` : Rendu visuel des conteneurs (`SuperContainer`, `StyledSurface`, `NeonSurface`, `InteractionEffectBox`, `SurfacePainters`).
  - `widgets/components/` : Widgets d'exécution (`SuperLayout`, `SuperValue`, `SuperAction`, `SuperListView`, `SuperTab`, `SuperTable`, `SuperTreeView`, `SuperChart`, et composants Material natifs sous `native/`).
  - `widgets/editing/` : Mode édition visuelle (assistants d'ajout `addition/`, chat IA `ai/vibe_chat_dialog.dart`, éditeurs de composants `components/`, éditeurs de styles `styles/`, slots éditables `slots/`, overlay de sélection/redimensionnement `overlay/`, historique undo/redo `history/`).
  - `ai/` : Client Gemini (`call_gemini.dart`) et pièces jointes (`vibe_chat_attachment.dart`).

---

## 3. Conventions de code Dart / Flutter impératives

1. **En-tête Dartdoc + directive `library;`** :
   - Tout fichier `.dart` dans `packages/super_container_layout/lib/` commence par un commentaire de documentation `///` en français résumant le rôle architectural du fichier, suivi immédiatement de la directive `library;` (obligatoire en Dart 3 pour respecter la règle de lint `dangling_library_doc_comments`).
   - Toutes les classes, énumérations, mixins, extensions et fonctions publiques doivent posséder un commentaire `///` concis.
2. **Immuabilité et validation des modèles** :
   - Toutes les classes de configuration (`ComponentConfig`, `ContainerStyle`, etc.) sont `@immutable`, protègent leurs collections avec `List.unmodifiable` / `Map.unmodifiable`, et implémentent `copyWith`, `toJson`, `toCompactJson`, `fromJson`, `validate()`, `operator ==` et `hashCode`.
3. **Architecture GenUI plate par identifiant** :
   - Ne jamais imbriquer d'arbres de widgets Flutter arbitraires dans le JSON : toutes les configurations vivent à plat dans `Appearance.components[id]`, `Appearance.styles[id]` et `Appearance.behaviors[id]`.
   - Toute lecture/écriture réactive d'un composant passe par les contrôleurs `ValueNotifier` gérés par `Registry` et synchronisés avec `AppearanceScope` / `TypedAppearanceScope`.
4. **Liaisons JSON (`JsonTextBinding` & `JsonListScope`)** :
   - Les chemins contenant le joker `[?]` sont résolus via `JsonListScope.resolveSelected(binding, scope, store)`, ce qui permet à la fois l'itération par ligne (dans `SuperListView`, `SuperTable`, `SuperTreeView`, `SuperTab`) et la sélection Maître / Détail hors de la liste.

---

## 4. Commandes de validation

- **Analyse statique du package** :
  ```powershell
  cd packages/super_container_layout ; flutter analyze
  ```
- **Exécution d'un test ciblé du package** :
  ```powershell
  cd packages/super_container_layout ; flutter test test/<nom_du_test>.dart
  ```
- **Analyse statique de l'application complète** :
  ```powershell
  flutter analyze
  ```
