# super_spec_forge

Application Flutter Desktop et bibliothèque Dart de conception de cahier des charges, d'objets métiers et de règles de gestion à partir d'une idée, guidée par un wizard multi-étapes d'agents IA spécialisés.

## Étapes du wizard IA

1. **Lexique métier** (`Ubiquitous Language Expert`) : définition des termes canoniques, synonymes à unifier, sigles et conventions de vocabulaire.
2. **Cadrage & Acteurs** (`Product Strategist`) : clarification de l'idée, objectifs, personas, contraintes et hors-périmètre.
3. **Cahier des charges** (`Business Analyst`) : modules fonctionnels, exigences (MoSCoW), cas d'usage et exigences non fonctionnelles.
4. **Objets métiers** (`Domain Modeler`) : entités structurées JSON Schema avec sous-objets, attributs typés (≤ 200/objet, ≤ 200 lignes/tableau), relations (`1:1`, `1:N`, `N:M`) et cycles de vie.
5. **Règles de gestion** (`Rule Architect`) : règles `RG-xxx` de validation, calcul, transition d'état, permission et déclencheur (`Quand / Si / Alors`).
6. **Revue & Export** (`Consistency Auditor`) : analyse de cohérence inter-étapes et export en Markdown (`.md`), JSON (`.json`), YAML « JSON Schemas Light » (`super_designer`) et dossier d'application sandboxée (`super_container_layout`).

## Lancement & Validation

```powershell
cd packages\super_spec_forge
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

