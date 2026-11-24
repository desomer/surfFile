# super_designer

Application autonome d'édition visuelle et IA combinant le moteur [`super_container_layout`](../super_container_layout) et le package d'extensions de composants [`super_container_extensions`](../super_container_extensions) (`SuperChart`, `SuperCode`, etc.).

## Lancement

```powershell
cd packages/super_designer
flutter run -d windows
```

La bannière du mode édition (`F12`) apparaît initialement en bas de la page et reste
déplaçable à la souris. Le chat Vibe IA et le menu du chemin restent accessibles
lorsqu'ils sont ouverts.

## Applications sandboxées et persistance

Lorsque `persistRepository: true` est activé (comportement par défaut du `main`),
`SuperDesignerApp` ouvre automatiquement la dernière application active gérée par
`SandboxedApplicationStore` (ou crée l'application par défaut), en isolant dans son dossier :
- `app.json` : manifeste de l'application ;
- `appearance.json` et `pages/<pageId>.json` : persistance paginée de l'apparence (`PagedFileAppearanceStore`) ;
- `repositories/` : magasin `JsonRepositoryStore` isolé.

Les systèmes de design personnalisés (`DESIGN.md`) restent partagés globalement via `CustomDesignSystemStore.tryDefaultStore()`.
Lors d'un changement d'application (création, clonage ou ouverture depuis la barre d'outils flottante)
comme lors d'une demande normale de fermeture de fenêtre, `SuperDesignerApp` vide les saisies
d'apparence et de repositories en cours (`flushBindings`) ; toute erreur de sauvegarde annule la fermeture.

Un hôte ou un test peut également fournir `repositoryDirectory` pour cibler un `JsonRepositoryStore` dédié,
ou omettre `persistRepository` pour une exécution purement en mémoire.

## Configuration de la clé Gemini en build Release

Dans le dépôt (`build\windows\x64\runner\Release\super_designer.exe`), l'exécutable retrouve automatiquement le fichier `env` quel que soit le dossier courant.

Si vous déployez le dossier Release hors du dépôt (le fichier `env` n'est pas embarqué par sécurité) :
- compilez avec `flutter build windows --release --dart-define=GEMINI_API_KEY=...`, ou
- placez un fichier `env` ou `.env` à côté de `super_designer.exe`, ou
- placez un fichier `env` dans `%USERPROFILE%\.super_container_layout\env`, ou
- définissez la variable d'environnement Windows `GEMINI_API_KEY`.

## Installateur Windows (Inno Setup)

Prérequis : Visual Studio avec les outils C++ de bureau et Inno Setup 6 (`winget install --id JRSoftware.InnoSetup --exact`).
Depuis la racine du dépôt :

```powershell
.\installer\build-installer.ps1 -App SuperDesigner
```

L'installateur généré est créé dans `..\..\build\installer\SuperDesigner-<version>-windows-x64-setup.exe` (à partir du script [SuperDesigner.iss](../../installer/SuperDesigner.iss)) et installe l'application dans `%LOCALAPPDATA%\Programs\SuperDesigner` sans élévation.