---
description: "Conventions d'architecture, contrats GenUI et checklist de modification pour le package super_container_layout."
applyTo: "packages/super_container_layout/**"
---

# Instructions spécifiques au package `super_container_layout`

Consultez [`packages/super_container_layout/ARCHITECTURE.md`](../../packages/super_container_layout/ARCHITECTURE.md) pour l'index complet des fichiers et [`packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md`](../../packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md) pour la grammaire JSON GenUI.

## 1. Convention de documentation Dartdoc
- Chaque fichier sous `packages/super_container_layout/lib/` doit débuter par un commentaire `///` en français expliquant le rôle du fichier et ses interactions avec les classes voisines, suivi de la directive `library;`.
- Documentez avec `///` toute classe, énumération, typedef ou méthode publique ajoutée ou modifiée.

## 2. Checklist complète pour ajouter ou modifier un composant
Lors de l'ajout d'un nouveau type de composant ou d'une nouvelle propriété persistée :
1. **Modèle (`lib/models/<composant>_config.dart`)** :
   - Étendre `ComponentConfig` avec `@immutable`, `componentType`, `validate()`, `copyWith()`, `toJson()`, `toCompactJson()`, `fromJson()`, `operator ==` et `hashCode`.
2. **Catalogue polymorphique (`lib/models/component_config.dart` & `lib/models/json_syntax.dart`)** :
   - Enregistrer le `ComponentConfigCodec` dans `ComponentConfigCatalog`.
   - Ajouter le type canonique et ses alias courts dans `JsonComponentType._aliases` (`lib/models/json_syntax.dart`).
3. **Apparence (`lib/theme/appearance.dart` & `lib/theme/default_appearance.dart`)** :
   - Ajouter les méthodes d'accès et de mise à jour immuable (`<component>Component(id)`, `with<Component>Component(id, config)`).
4. **Registre et contrat de duplication (`lib/models/registry.dart`)** :
   - Ajouter l'entrée dans `EditorConfigKind`, `EditorConfigRef`, `ComponentDuplicationContract`, la map de `ValueNotifier` dans `Registry`, `appearanceSnapshot()`, `_syncAppearance()`, et enregistrer le builder dans `Registry.bootstrap()`.
5. **Graphe de pages et fabrique de slots (`lib/services/pages/editor_page_graph.dart` & `lib/widgets/components/super_layout/slot_implementation.dart`)** :
   - Mettre à jour la collecte des identifiants enfants, la duplication profonde et la suppression sans orphelins dans `EditorPageGraph`.
   - Raccorder le rendu et les actions de menu contextuel dans `SlotFactory` / `EditorSlot`.
6. **Widgets d'exécution et d'édition (`lib/widgets/components/` & `lib/widgets/editing/`)** :
   - Créer le widget runtime dans `lib/widgets/components/`, le configurateur d'ajout dans `lib/widgets/editing/addition/` (et son formulaire dans `addition/forms/`), et l'éditeur de propriétés dans `lib/widgets/editing/components/`.
   - Exporter les nouveaux fichiers publics dans `lib/super_container_layout.dart`.
7. **Guide IA & Tests** :
   - Documenter le format JSON dans `packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md`.
   - Ajouter les tests unitaires et widgets dans `packages/super_container_layout/test/`.

## 3. Règles pour les liaisons JSON (`JsonTextBinding` & `JsonListScope`)
- Toujours résoudre les liaisons via `JsonListScope.resolveSelected(binding, scope, store)` afin de supporter simultanément :
  - l'indice de ligne fourni par un parent itératif (`SuperListView`, `SuperTable`, `SuperTreeView`, `SuperTab` dynamique) ;
  - le repository hérité (`binding.inheritsRepository`, c'est-à-dire `repositoryId.isEmpty`) ;
  - la ligne sélectionnée (Maître / Détail) stockée dans `JsonArrayBinding` lorsque le composant est placé en dehors de la collection.

## 4. Règles pour les styles de surface et états (`ContainerStyle` & `SurfaceStyleStates`)
- Les surcharges d'états (`hover`, `selected`, `automatic.contentHover`, `automatic.focused`, `automatic.disabled`, `automatic.readOnly`, et états métier `named`) n'écrasent que les groupes explicitement listés dans `properties`.
- Veiller à préserver la compatibilité avec `AppearanceTransfer.applyVibe` (fusion incrémentale des patches JSON générés par l'IA).
