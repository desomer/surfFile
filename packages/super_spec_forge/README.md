# super_spec_forge

Application Flutter Desktop et bibliothèque Dart de conception de cahier des charges, d'objets métiers et de règles de gestion à partir d'une idée, guidée par un wizard multi-étapes d'agents IA spécialisés.

## Étapes du wizard IA

1. **Lexique métier** (`Ubiquitous Language Expert`) : définition des termes canoniques, synonymes à unifier, sigles et conventions de vocabulaire.
2. **Cadrage & Acteurs** (`Product Strategist`) : clarification de l'idée, objectifs, personas, contraintes et hors-périmètre.
3. **Cahier des charges** (`Business Analyst`) : modules fonctionnels, exigences (MoSCoW), cas d'usage et exigences non fonctionnelles.
4. **Objets métiers** (`Domain Modeler`) : entités structurées JSON Schema avec sous-objets, attributs typés (≤ 200/objet, ≤ 200 lignes/tableau), relations (`1:1`, `1:N`, `N:M`) et cycles de vie.
5. **Règles de gestion** (`Rule Architect`) : règles `RG-xxx` de validation, calcul, transition d'état, permission et déclencheur (`Quand / Si / Alors`).
6. **Revue & Export** (`Consistency Auditor`) : analyse de cohérence inter-étapes et export en Markdown (`.md`), JSON (`.json`), YAML « JSON Schemas Light » (`super_designer`) et dossier d'application sandboxée (`super_container_layout`).

## Persistance par dossier & intégration Git

Les données sont stockées dans un **dossier Workspace sélectionnable** (par défaut `~/.super_spec_forge`, ou tout dépôt Git choisi via le sélecteur de workspace dans la barre d'application) :

```text
<workspace>/
├── .gitignore                          # Généré si absent (.local/, exports/, *.tmp.*)
├── workspace.json                      # Métadonnées du workspace
├── .local/state.json                   # Dernier projet actif sur cette machine (ignoré par Git)
├── glossary/
│   ├── glossary.json                   # Conventions & ambiguïtés
│   ├── chat.json                       # Historique du chat IA du glossaire
│   └── terms/<slug>.json               # 1 fichier par terme
├── dictionary/
│   ├── preferences.json                # Préférences globales de modélisation
│   └── rules/<slug>.json               # 1 fichier par règle technique
└── projects/<project-slug>/
    ├── project.json                    # Métadonnées du projet
    ├── spec/
    │   ├── lexicon.json
    │   ├── vision.json
    │   ├── cahier_des_charges.json
    │   ├── model_preferences.json
    │   ├── coherence_issues.json
    │   ├── business_objects/<slug>.json
    │   └── business_rules/<slug>.json
    ├── chats/                          # Historiques IA par étape et chat global
    └── attachments/                    # Pièces jointes dédupliquées
```

## Lancement & Validation

```powershell
cd packages\super_spec_forge
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

