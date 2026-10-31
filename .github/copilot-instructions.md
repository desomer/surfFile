# Instructions GitHub Copilot — SurfFile & `super_container_layout`

Ce dépôt contient l'application Flutter Desktop **SurfFile** (`lib/`) et le package **super_container_layout** (`packages/super_container_layout/`).

## Guides de référence
- **Architecture et index des 167 fichiers du package** : [`packages/super_container_layout/ARCHITECTURE.md`](../packages/super_container_layout/ARCHITECTURE.md)
- **Spécification JSON GenUI / Vibe IA** : [`packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md`](../packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md)
- **Instructions détaillées pour `super_container_layout`** : [`.github/instructions/super-container-layout.instructions.md`](instructions/super-container-layout.instructions.md)

## Règles essentielles
1. **En-tête de fichier Dart 3 (`library;`)** : Tout fichier dans `packages/super_container_layout/lib/` doit commencer par un bloc Dartdoc `///` en français décrivant son rôle, suivi immédiatement de `library;` avant les `import` (évite le lint `dangling_library_doc_comments`).
2. **Modèle plat par ID (`Appearance`)** : Les configurations de composants (`Appearance.components`), de styles (`Appearance.styles`) et de comportements (`Appearance.behaviors`) sont indexées à plat par identifiant d'instance et synchronisées via `Registry`.
3. **Immuabilité et sérialisation** : Tout modèle dans `lib/models/` ou `lib/theme/` doit être `@immutable`, valider ses invariants dans `validate()` et `fromJson()`, et supporter `toJson()` ainsi que `toCompactJson()` (utilisé par l'export compact et `AppearanceTransfer.applyVibe`).
4. **Validation** : Toujours vérifier les changements avec `flutter analyze` et un test ciblé via `flutter test`.
