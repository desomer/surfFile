# Guide pour IA : Modéliser les Comportements, Événements, Validateurs et Actions (`super_container_layout`)

Ce document est la spécification technique normative destinée à une Intelligence Artificielle. Il définit comment **concevoir, cibler, combiner et sérialiser en JSON les comportements interactifs et réactifs** (`behaviors`) dans `super_container_layout` : événements déclencheurs (`BehaviorEvent`), conditions de garde et prédicats (`BehaviorValidator`), actions polymorphes (`BehaviorAction` — 20 types), branche `elseAction`, anti-rebond `debounceMs`, transformation de vue de collections côté client (`CollectionViewTransform`) et scripts contrôlés QuickJS.

Il complète :
- [`SCREEN_JSON_AI_GUIDE.md`](SCREEN_JSON_AI_GUIDE.md) (grammaire GenUI des composants, layouts, styles et états visuels) ;
- [`REPOSITORY_JSON_AI_GUIDE.md`](REPOSITORY_JSON_AI_GUIDE.md) (modélisation des Repositories JSON, `jsonSchema`, `@calculs` et protocole `"repositories"`) ;
- [`SCREEN_DESIGN_AI_GUIDE.md`](SCREEN_DESIGN_AI_GUIDE.md) (Design System Material 3 Desktop et micro-interactions).

> **Règle stricte (« zéro hallucination »)** : respecte scrupuleusement les types, noms de clés, couplages `event` $\leftrightarrow$ `action` et invariants de `ComponentBehavior.validate()`, `BehaviorValidatorCatalog`, `BehaviorActionCatalog`, `BehaviorDispatcher` et `CollectionViewTransform` documentés ci-dessous. N'invente **aucun** callback Dart inline, **aucun** événement ou opérateur absent des tables normatives, et **aucune** écriture vers un attribut calculé `@...`.

---

## 1. Architecture plate `behaviors` & Protocole Vibe (`applyVibe`)

### 1.1. Structure JSON canonique d'une entrée de `behaviors`

Dans le modèle GenUI plat (`Appearance`), tous les comportements vivent dans le dictionnaire racine **`"behaviors"`** (`Map<String, List<ComponentBehavior>>`), indexé par l'**identifiant technique** du composant porteur :

```json
{
  "behaviors": {
    "<componentId>": [
      {
        "id": "b-action-explicite",
        "event": "onTap",
        "enabled": true,
        "validator": {
          "type": "otherIsFill",
          "targetComponentId": "input-email"
        },
        "action": {
          "type": "goToPage",
          "pagePath": "/confirmation",
          "pageName": "Confirmation"
        }
      }
    ]
  }
}
```

Chaque objet `ComponentBehavior` possède **7 propriétés possibles** :

| Clé JSON | Type | Requis | Défaut | Rôle et contraintes |
| :--- | :--- | :---: | :---: | :--- |
| **`id`** | `string` | Oui | `""` | Identifiant unique et descriptif du comportement en `kebab-case` (ex. `"b-save-client"`, `"b-filter-search"`). |
| **`event`** | `string` | Oui | `"onTap"` | Événement déclencheur canonique parmi les **16 `BehaviorEvent`** (l'ancienne clé `"trigger"` est acceptée en lecture seule pour rétrocompatibilité : **toujours émettre `"event"`**). |
| **`enabled`** | `boolean` | Non | `true` | Active ou suspend le comportement (omis en export compact lorsqu'il vaut `true`). |
| **`validator`** | `object` | Non | `null` | Condition de garde polymorphe (`BehaviorValidator`). Pour un événement impératif, l'`action` ne s'exécute que si `validator` s'évalue à `true` (et `elseAction` éventuelle si `false`). Pour `onBinding` sur `sortCollection` / `filterCollection`, sert de condition d'activation ou de prédicat par ligne (voir section 4.5). |
| **`action`** | `object` | Oui | — | Action polymorphe identifiée par son discriminateur `"type"` parmi les **20 `BehaviorAction`**. |
| **`elseAction`** | `object` | Non | `null` | Action impérative exécutée lorsque `validator` s'évalue à `false`. Requiert `validator != null`, un événement impératif, et une action non purement déclarative. |
| **`debounceMs`** | `integer` | Non | `null` | Anti-rebond en millisecondes (`>= 0`) sur un événement impératif (ex. `300` sur `onChanged` $\rightarrow$ `searchProvider`). Annule le déclenchement précédent et réévalue `validator` à l'échéance. |

### 1.2. Quel identifiant cibler dans `behaviors["<id>"]` ?

Cible toujours l'identifiant du composant qui porte réellement l'interaction ou la règle réactive :

| Cible fonctionnelle | Clé exacte dans `"behaviors"` | Usage typique |
| :--- | :--- | :--- |
| **Bouton, champ, indicateur, carte, layout, panneau** | `"<componentId>"` | `onTap`, `onChanged`, `onSubmitted`, `onHover` (`onTooltip`), `onBinding` (`bindState`, `bindZoneSize` sur un `SuperLayout`). |
| **Collection `SuperListView` (conteneur global)** | `"<listId>"` | `onSelected` (sélection d'une ligne), **`onBinding` avec `sortCollection` ou `filterCollection`**, `bindState`. |
| **Ligne entière d'une `SuperListView` (`IterableContent` implicite)** | **`"<listId>:item"`** | `onTap`, `onDoubleTap`, `onLongPress`, `onHoverEnter`, `onHover` (`onTooltip` lié à la ligne `"clients[?].notes"`). Le `JsonListScope` de la ligne cliquée/survolée est automatiquement actif. |
| **Collection `SuperTable` ou `SuperTreeView` (conteneur global)** | `"<tableId>"` / `"<treeId>"` | `onSelected`, **`onBinding` avec `sortCollection` ou `filterCollection`** (sur `SuperTable`), `onExpanded` / `onCollapsed` (sur `SuperTreeView`). |
| **Ligne entière d'une `SuperTable` ou d'un `SuperTreeView`** | **`"<itemId>"`** *(valeur de `components[id].itemId`, ex. `"table-clients:item"`)* | `onDoubleTap` pour ouvrir le détail de la ligne, `onHover` (`onTooltip` par ligne). |
| **Barre d'onglets `SuperTab` (conteneur global)** | `"<tabId>"` | `onSelected` (reçoit `index`, `previousIndex` et `tabId`). |
| **Onglet individuel ou destination (`SuperTab`, `NavigationRail`, `BottomNavigationBar`)** | `"<actionSlotId>"` *(ID du composant `"action"` placé dans `tabs` / `destinations`)* | `onTap` ou `onSelected` spécifique à cet onglet ou cette destination. |

### 1.3. Règles de fusion incrémentale en mode Vibe (`applyVibe`)

1. **Ordre d'émission SSE live** : dans `"vibe"`, émets toujours `"behaviors"` **en dernier** (avec `"usages"`), après `"pageCatalog"`, `"styles"` et `"components"`, afin que tous les composants ciblés (`<componentId>`, `targetComponentId`, `expectedComponentId`) existent déjà.
2. **Remplacement atomique de la liste par composant** :
   - Fournir `"behaviors": { "btn-save": [ ... ] }` **remplace intégralement** la liste des comportements attachés à `"btn-save"`.
   - **Conséquence critique** : si `"btn-save"` possède déjà un comportement dans l'`ÉTAT ACTUEL (JSON)` (ex. un `onTooltip`) et que tu veux lui ajouter un `onTap`, tu **dois inclure les deux entrées** dans le tableau `"behaviors": { "btn-save": [ <existant>, <nouveau> ] }`.
   - Les composants **non mentionnés** dans `"behaviors"` conservent leurs comportements existants intacts.
3. **Suppression des comportements d'un composant** :
   - Émets `"behaviors": { "btn-save": null }` ou `"behaviors": { "btn-save": [] }` pour retirer tous les comportements de `"btn-save"`.
   - Lorsqu'un composant est supprimé (`"components": { "<id>": null }`), le moteur purge automatiquement `behaviors["<id>"]` ainsi que `behaviors["<id>:item"]`.
4. **Réécriture automatique des alias de `"repositories"`** :
   - Si tu crées un repository dans le même tour avec un alias `snake_case` (ex. `"crm_clients"`), tu peux utiliser directement cet alias dans **tous** les champs de liaison des comportements :
     - `"binding": "crm_clients:clients[?].statut"` ou `{"repositoryId": "crm_clients", "path": "..."}` (dans `validator`, `predicate`, `addArrayItem`, `creationDefault`, `bindState`, `bindZoneSize`, `onTooltip`) ;
     - `"expectedBinding": "crm_clients:filters.seuil"` (dans un validateur binaire) ;
     - `"repositoryId": "crm_clients"` (dans une action `"runJavaScript"`).
   - `VibeRepositoryApplier` réécrit automatiquement l'alias vers l'identifiant réel de 32 caractères hexadécimaux avant l'application du patch `"vibe"`.

### 1.4. Pipeline d'exécution runtime (`BehaviorDispatcher`)

Lorsqu'un événement impératif survient sur un composant :
1. **Garde du mode édition (`StyleEditScope`)** : tous les comportements impératifs, les états `invisible` et les tris/filtres `CollectionViewTransform` sont **suspendus en mode édition visuelle** afin que l'utilisateur puisse sélectionner, inspecter et éditer librement chaque composant sans déclencher de navigation ni masquer d'éléments.
2. **Garde d'état (`ComponentBehaviorStateScope`)** : si le composant (ou l'un de ses ancêtres) est actuellement `disabled` ou `invisible`, aucun comportement impératif ne se déclenche.
3. **Protection anti-boucle (`maxReentrancyDepth = 8`)** : `BehaviorDispatcher` bloque toute réentrance dépassant une profondeur de 8 pour une même paire `(componentId, event)` (empêche par exemple une boucle infinie `onChanged` $\rightarrow$ script $\rightarrow$ `onChanged`).
4. **Exécution séquentielle ordonnée & anti-rebond** : les comportements activés (`enabled: true`) correspondant à `event` sont parcourus **dans l'ordre exact de la liste JSON**. Les comportements avec `debounceMs > 0` planifient un timer par `(componentId, behavior.id, event)` sans bloquer les comportements immédiats. À l'exécution, `BehaviorValidatorEvaluator` évalue `validator` : si `true` (ou absent), `action` s'exécute ; si `false` et `elseAction` est définie, `elseAction` s'exécute.

---

## 2. Référence exhaustive des Événements (`BehaviorEvent` — 16 types)

Le moteur distingue strictement **deux familles d'événements** qui ne se mélangent pas (sauf `sortCollection` et `filterCollection`, hybrides par conception) :
- **13 événements impératifs** (`isImperative: true`) : compatibles avec les **16 actions impératives** et un `validator` de garde optionnel (plus `elseAction` et `debounceMs`) ;
- **3 événements déclaratifs / réactifs** (`isImperative: false`) : réservés exclusivement à leurs actions dédiées.

### 2.1. Les 13 événements impératifs

| `event` canonique *(à émettre)* | Alias tolérés en lecture | Catégorie | Déclenchement, curseur & comportement natif | Composants recommandés & données `event.data` transmises |
| :--- | :--- | :--- | :--- | :--- |
| **`"onTap"`** | `"click"`, `"tap"` | Gestes | Clic principal ou tap. Active automatiquement le curseur pointeur (`click`) et déduplique les slots imbriqués de même ID. Préserve l'interaction native des champs/contrôles enfants. | **Tous composants**. Sur `SuperValue` : `{value, previousValue}`. |
| **`"onDoubleTap"`** | `"doubleClick"`, `"doubleTap"` | Gestes | Double-clic rapide. Active le curseur pointeur. Si `"onTap"` est aussi présent sur le même composant, `"onTap"` reste émis et `"onDoubleTap"` s'exécute en complément au second clic. | **Tous composants** (idéal sur `<listId>:item`, `<tableItemId>` ou nœud d'arbre pour ouvrir une fiche). |
| **`"onLongPress"`** | `"longPress"` | Gestes | Appui maintenu (`kLongPressTimeout`). Active le curseur pointeur et annule le clic simple associé. | **Tous composants** (actions secondaires, menu contextuel métier). |
| **`"onHoverEnter"`** | `"hoverEnter"` | Survol | Entrée du pointeur souris dans la boîte du composant (**sans** curseur pointeur forcé). | **Tous composants** (prévisualisation, mise en évidence croisée). |
| **`"onHoverExit"`** | `"hoverExit"` | Survol | Sortie du pointeur souris hors de la boîte du composant. | **Tous composants** (nettoyage / `reset` d'une mise en évidence). |
| **`"onSelected"`** | `"selected"` | Sélection | Sélection d'un élément de collection, d'un onglet, d'une destination, d'un choix ou d'un point de graphique. | - `SuperListView` & `<listId>:item` : `{index, previousIndex}` *(toujours l'**indice source** du repository, même trié/filtré)*<br>- `SuperTable` & `<itemId>` : `{index, previousIndex}`<br>- `SuperTreeView` & `<itemId>` : `{nodePath, rootIndex, previousNodePath}`<br>- `SuperChart` : `{index, previousIndex?, label?}`<br>- `SuperTab` : `{index, previousIndex, tabId}` (et `{index, previousIndex}` sur l'onglet `"action"`)<br>- `NavigationRail` / `BottomNavigationBar` : `{index, previousIndex, destinationId}`<br>- `SuperValue` (`choice`) : `{value, previousValue, isValid}` |
| **`"onChanged"`** | `"changed"` | Valeur & saisie | Modification de la valeur par une action directe de l'utilisateur (ne se redéclenche **pas** lors d'une mise à jour externe du repository). | - `SuperValue` (`input`, `checkbox`, `switch`, `choice`) : `{value, previousValue, isValid}`<br>- `Expansible` & `Menu` : `{expanded, value, previousValue}` |
| **`"onSubmitted"`** | `"submitted"` | Valeur & saisie | Validation clavier (touche `Entrée`) dans un champ de saisie texte. | `SuperValue` (`kind: "text"`, `mode: "input"`) : `{value, isValid}`. |
| **`"onFocus"`** | `"focus"` | Focus | Prise du focus clavier par le composant. | `SuperValue` focusable : `{value, isValid}`. |
| **`"onBlur"`** | `"blur"` | Focus | Perte du focus clavier (idéal pour lancer une sauvegarde ou validation de sortie de champ). | `SuperValue` focusable : `{value, isValid}`. |
| **`"onExpanded"`** | `"expanded"` | Ouverture | Ouverture / dépliage d'un accordéon, d'un menu déroulant ou d'un nœud d'arbre. Sur `Expansible` et `Menu`, émis juste avant `onChanged`. | - `Expansible` & `Menu` : `{expanded: true, value: true, previousValue: false}`<br>- `SuperTreeView` : `{nodePath, rootIndex, expanded: true}` |
| **`"onCollapsed"`** | `"collapsed"` | Fermeture | Fermeture / repliage d'un accordéon, d'un menu ou d'un nœud d'arbre. Sur `Expansible` et `Menu`, émis juste avant `onChanged`. | - `Expansible` & `Menu` : `{expanded: false, value: false, previousValue: true}`<br>- `SuperTreeView` : `{nodePath, rootIndex, expanded: false}` |
| **`"onMount"`** | `"mount"` | Cycle de vie | Exécuté **une seule fois** après le premier frame d'affichage initial du composant (hors mode édition, si ni `disabled` ni `invisible`). Réarmé uniquement si l'ID du composant change. | **Tous composants** (chargement initial `datasource` / `searchProvider` à l'ouverture d'une page). |

### 2.2. Les 3 événements déclaratifs / réactifs (couplages stricts)

Toute violation des couplages ci-dessous lève immédiatement une `FormatException` dans `ComponentBehavior.validate()` :

| `event` canonique | Alias toléré | Actions exclusivement autorisées | Actions interdites (erreur `FormatException`) |
| :--- | :--- | :--- | :--- |
| **`"onHover"`** | `"hover"` | **Uniquement `"onTooltip"`** (info-bulle déclarative native sans curseur clic). | Toute autre action (`setStyle`, `setVisibility`, `emitEvent`…). Pour une action impérative au survol, utilise **`"onHoverEnter"`** / **`"onHoverExit"`**. |
| **`"onBinding"`** | `"binding"` | **Uniquement `"bindState"`, `"bindZoneSize"`, `"sortCollection"` et `"filterCollection"`**. | Toute autre action (`setStyle`, `runJavaScript`, `goToPage`…). |
| **`"onCreate"`** | `"create"` | **Uniquement `"creationDefault"`** (valeur initiale d'un champ `SuperValue` lors d'un ajout de ligne). | Toute autre action. |

---

## 3. Référence exhaustive des Validateurs (`BehaviorValidator`)

Un `BehaviorValidator` est un arbre booléen immuable et sérialisable utilisé à deux endroits :
1. Dans **`behavior.validator`** : condition de garde avant une action impérative (ou condition d'activation / prédicat par ligne en `onBinding`) ;
2. Dans **`filterCollection.predicate`** : prédicat évalué pour chaque ligne d'un `SuperListView` ou d'un `SuperTable`.

### 3.1. Les 3 sources de valeur (`self`, `component`, `binding`)

Chaque validateur unitaire (`ValueBehaviorValidator`) inspecte une valeur issue de l'une des **3 sources** suivantes. Privilégie systématiquement le **`type` court canonique** ci-dessous :

| Source | Préfixe du `type` | Champs requis / interdits sur le validateur | Résolution runtime (`BehaviorValidatorEvaluator`) |
| :--- | :--- | :--- | :--- |
| **1. Composant courant (`self`)** | `<opérateur>`<br>*(ex. `"isFill"`, `"equals"`, `"isTrue"`, `"isValid"`)* | - `targetComponentId` **interdit**<br>- `binding` **interdit** | Lit `executionData["value"]` / `executionData["isValid"]` de l'événement courant en priorité, sinon l'instance montée dans `ComponentRuntimeValueRegistry` (même ligne `JsonListScope` puis global), sinon le `binding` déclaré sur `Appearance.components[id]`. |
| **2. Autre composant (`component`)** | `other<Opérateur>`<br>*(ex. `"otherIsFill"`, `"otherEquals"`, `"otherIsValid"`)* | - **`"targetComponentId"` requis** *(chaîne non vide ; alias `"targetId"` toléré)*<br>- `binding` **interdit** | Résout `"targetComponentId"` dans `ComponentRuntimeValueRegistry` en privilégiant **l'instance montée dans la même ligne `JsonListScope`**, puis l'instance globale hors liste, puis le `binding` configuré dans `Appearance.components[targetComponentId]`. **Bonus conteneur (`otherIsValid` / `otherIsInvalid`)** : si `targetComponentId` désigne un conteneur (`Layout`, `Card`, `Tab`, `Conditional`, `Scaffold`, `A4`), vérifie récursivement la validité de tous ses descendants validables ! |
| **3. Liaison repository (`binding`)** | `binding<Opérateur>`<br>*(ex. `"bindingIsFill"`, `"bindingEquals"`, `"bindingContains"`)* | - **`"binding"` requis** *(chaîne `"repo:chemin"` / `"chemin"` ou objet `{"repositoryId", "path"}`)*<br>- `targetComponentId` **interdit**<br>- **`isValid` et `isInvalid` interdits** | En filtrage de ligne, lit d'abord directement le champ en mémoire dans `rowItem` (ultra-rapide, synchrone), sinon résout les `[?]` via `JsonListScope.resolveSelected` + `JsonRepositoryStore` (supporte les scalaires, tableaux, objets et `@calculs`). |

*(Note : la forme générique verbeuse `{"type": "value", "source": "self"|"component"|"binding", "operator": "equals", ...}` est aussi décodée, mais le moteur normalise toujours vers le `type` court canonique comme `"otherEquals"` ou `"bindingEquals"`.)*

### 3.2. Matrice complète des 18 opérateurs (`52` types courts canoniques)

| Opérateur | `self` | `component` (`+ targetComponentId`) | `binding` (`+ binding`) | Valeur attendue (`value` / dynamique) | Sémantique exacte & contraintes `validate()` |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Est vide** | `"isEmpty"` | `"otherIsEmpty"` | `"bindingIsEmpty"` | **Interdite** | `true` si `null`, `""`, chaîne d'espaces `"   "`, `[]` ou `{}`. **Attention** : `0`, `0.0`, `false` et `true` ne sont **jamais** vides (`isEmpty == false`). |
| **Est rempli** | `"isFill"` *(alias `"isFilled"`, `"isNotEmpty"`)* | `"otherIsFill"` *(alias `"otherIsFilled"`, `"otherIsNotEmpty"`)* | `"bindingIsFill"` *(alias `"bindingIsFilled"`, `"bindingIsNotEmpty"`)* | **Interdite** | Exactement `!isEmpty` : chaîne contenant au moins 1 caractère non blanc, collection non vide, ou tout nombre/booléen non nul (y compris `0`). |
| **Est vrai** | `"isTrue"` | `"otherIsTrue"` | `"bindingIsTrue"` | **Interdite** | `true` si booléen `true` ou chaîne insensible à la casse parmi `"true"`, `"1"`, `"yes"`, `"oui"`. |
| **Est faux** | `"isFalse"` | `"otherIsFalse"` | `"bindingIsFalse"` | **Interdite** | `true` si booléen `false` ou chaîne insensible à la casse parmi `"false"`, `"0"`, `"no"`, `"non"`. *(Note : `null` retourne `false` à la fois pour `isTrue` et `isFalse`.)* |
| **Est valide** | `"isValid"` | `"otherIsValid"` | *(Interdit)* | **Interdite** | `true` si le composant existe et satisfait ses contraintes natives (`required`, `minLength`, `pattern`, `format`, `minimum`/`maximum` et `jsonSchema` lié). Sur un conteneur (`Layout`, `Card`, `Tab`…), vérifie récursivement tous ses champs descendants validables. |
| **Est invalide** | `"isInvalid"` | `"otherIsInvalid"` | *(Interdit)* | **Interdite** | `true` si le composant (ou au moins un descendant validable d'un conteneur) est introuvable ou en erreur de validation native (`!isValid`). |
| **Est égal à** | `"equals"` | `"otherEquals"` | `"bindingEquals"` | **Requise** *(`null` autorisé)* | Égalité JSON profonde avec coercition souple nombre $\leftrightarrow$ chaîne numérique (`42` == `"42"`) et booléen $\leftrightarrow$ `"true"`/`"false"`. Supporte `"caseSensitive"`. |
| **Est différent de** | `"notEquals"` | `"otherNotEquals"` | `"bindingNotEquals"` | **Requise** *(`null` autorisé)* | Négation exacte de `equals`. Supporte `"caseSensitive"`. |
| **Contient** | `"contains"` | `"otherContains"` | `"bindingContains"` | **Requise** *(non `null`)* | - Si la valeur inspectée est une **`List` / `Iterable`** (ex. choix multiple ou tableau JSON de tags) : `true` si au moins un élément est égal à la cible (`_valuesEqual`).<br>- Sinon : sous-chaîne sur `toString()`. Supporte `"caseSensitive"`. |
| **Commence par** | `"startsWith"` | `"otherStartsWith"` | `"bindingStartsWith"` | **Requise** *(`string` si statique)* | Préfixe textuel (`toString().startsWith(...)`). Supporte `"caseSensitive"`. |
| **Strictement `>`** | `"greaterThan"` | `"otherGreaterThan"` | `"bindingGreaterThan"` | **Requise** *(nombre fini ou date ISO 8601)* | Compare deux nombres finis (ou chaînes numériques) **ou** deux dates ISO 8601 (`"2026-05-19"` / `DateTime`). Retourne `false` si incompatible. |
| **Strictement `<`** | `"lessThan"` | `"otherLessThan"` | `"bindingLessThan"` | **Requise** *(nombre fini ou date ISO 8601)* | Compare deux nombres finis **ou** deux dates ISO 8601 (`left < right`). |
| **Supérieur ou égal `>=`** | `"greaterOrEqual"` | `"otherGreaterOrEqual"` | `"bindingGreaterOrEqual"` | **Requise** *(nombre fini ou date ISO 8601)* | Compare deux nombres finis **ou** deux dates ISO 8601 (`left >= right`). |
| **Inférieur ou égal `<=`** | `"lessOrEqual"` | `"otherLessOrEqual"` | `"bindingLessOrEqual"` | **Requise** *(nombre fini ou date ISO 8601)* | Compare deux nombres finis **ou** deux dates ISO 8601 (`left <= right`). |
| **Nombre d'éléments `=`** | `"countEquals"` | `"otherCountEquals"` | `"bindingCountEquals"` | **Requise** *(entier `>= 0`)* | Compare la taille (`List.length`, `Map.length`, `String.length`, `null` $\rightarrow$ `0`) à un entier. |
| **Nombre d'éléments `>`** | `"countGreaterThan"` | `"otherCountGreaterThan"` | `"bindingCountGreaterThan"` | **Requise** *(entier `>= 0`)* | Vérifie `count > expected` (ex. `"bindingCountGreaterThan"` avec `"value": 0` pour vérifier qu'un tableau contient au moins 1 ligne). |
| **Nombre d'éléments `<`** | `"countLessThan"` | `"otherCountLessThan"` | `"bindingCountLessThan"` | **Requise** *(entier `>= 0`)* | Vérifie `count < expected`. |
| **Expression régulière** | `"matchesRegex"` | `"otherMatchesRegex"` | `"bindingMatchesRegex"` | **Requise** *(`string` RegExp valide non vide)* | Teste `RegExp(pattern, caseSensitive: caseSensitive).hasMatch(value.toString())`. Une regex invalide lève `FormatException` dès `validate()`. |

### 3.3. Valeur attendue statique vs dynamique & sensibilité à la casse

Sur les **12 opérateurs binaires** (`equals`, `notEquals`, `contains`, `startsWith`, `greaterThan`, `lessThan`, `greaterOrEqual`, `lessOrEqual`, `countEquals`, `countGreaterThan`, `countLessThan`, `matchesRegex`), la valeur de droite peut provenir d'**exactement une seule** des 3 propriétés mutuellement exclusives suivantes :

1. **`"value"`** *(constante JSON statique : `string`, `number`, `boolean`, `list`, `map`, ou `null` sur `equals`/`notEquals` ; alias `"expectedValue"` toléré)* :
   ```json
   { "type": "bindingEquals", "binding": "clients[?].statut", "value": "actif" }
   ```
2. **`"expectedComponentId"`** *(valeur runtime courante d'un autre composant monté, ex. barre de recherche ou sélecteur de filtre)* :
   ```json
   {
     "type": "bindingContains",
     "binding": "clients[?].nom",
     "expectedComponentId": "input-search",
     "caseSensitive": false
   }
   ```
3. **`"expectedBinding"`** *(attribut lu dynamiquement dans un repository JSON)* :
   ```json
   {
     "type": "bindingGreaterThan",
     "binding": "clients[?].caAnnuel",
     "expectedBinding": "crm_clients:filters.caMinimum"
   }
   ```

> **Règle d'exclusivité stricte** :
> - Ne combine **jamais** `"value"` avec `"expectedComponentId"` ou `"expectedBinding"`, ni `"expectedComponentId"` avec `"expectedBinding"` (`FormatException`).
> - N'ajoute **jamais** `"expectedComponentId"` ni `"expectedBinding"` sur un opérateur unaire (`isEmpty`, `isFill`, `isTrue`, `isFalse`, `isValid`, `isInvalid`).
> - **Casse par défaut (`"caseSensitive": true`)** : dans un `BehaviorValidator`, les comparaisons textuelles sont **sensibles à la casse par défaut**. Pour une barre de recherche utilisateur (`contains`, `startsWith`), **ajoute systématiquement `"caseSensitive": false`**.

### 3.4. Les 3 validateurs composites logiques (`all`, `any`, `not`)

Les validateurs peuvent s'imbriquer sans limite de profondeur avec évaluation court-circuitée :

- **`"all"` (ET logique — liste `"validators"` au pluriel, au moins 1 élément)** :
  ```json
  {
    "type": "all",
    "validators": [
      { "type": "otherIsValid", "targetComponentId": "input-email" },
      { "type": "otherIsValid", "targetComponentId": "input-montant" },
      { "type": "bindingIsFalse", "binding": "crm_clients:clients[?].verrouille" }
    ]
  }
  ```
- **`"any"` (OU logique — liste `"validators"` au pluriel, au moins 1 élément)** :
  ```json
  {
    "type": "any",
    "validators": [
      { "type": "bindingContains", "binding": "clients[?].nom", "expectedComponentId": "input-search", "caseSensitive": false },
      { "type": "bindingContains", "binding": "clients[?].entreprise", "expectedComponentId": "input-search", "caseSensitive": false },
      { "type": "bindingContains", "binding": "clients[?].ville", "expectedComponentId": "input-search", "caseSensitive": false }
    ]
  }
  ```
- **`"not"` (NON logique — objet `"validator"` au singulier !)** :
  ```json
  {
    "type": "not",
    "validator": {
      "type": "bindingEquals",
      "binding": "clients[?].statut",
      "value": "archive"
    }
  }
  ```
  *(Attention : `"all"` et `"any"` utilisent `"validators": [ ... ]` au **pluriel**, tandis que `"not"` utilise `"validator": { ... }` au **singulier**.)*

---

## 4. Catalogue exhaustif des 20 Actions (`BehaviorAction`)

### Vue synoptique des 20 actions et de leurs événements autorisés

| `action.type` | Mode | Événements (`event`) autorisés | Rôle résumé |
| :--- | :---: | :--- | :--- |
| **`"goToPage"`** | Impératif | Les 13 événements impératifs | Naviguer vers une page standard, A4 ou modale (`dialog`, `bottomSheet`, `sideSheet`). |
| **`"goBack"`** | Impératif | Les 13 événements impératifs | Fermer une page modale (`dialog`, `bottomSheet`, `sideSheet`) ou revenir à la page précédente (`fallbackPagePath` optionnel). |
| **`"generatePdf"`** | Impératif | Les 13 événements impératifs | Générer et exporter un fichier `.pdf` depuis une page `"a4Document"`. |
| **`"emitEvent"`** | Impératif | Les 13 événements impératifs | Publier un événement métier sur le `SuperEventBus` de l'application hôte. |
| **`"showMessage"`** | Impératif | Les 13 événements impératifs | Afficher un toast / `SnackBar` Material 3 (`info`, `success`, `warning`, `error`), fixe ou lié. |
| **`"copyToClipboard"`** | Impératif | Les 13 événements impératifs | Copier un texte fixe, la valeur d'un composant ou d'une liaison dans le presse-papiers. |
| **`"setStyle"`** | Impératif | Les 13 événements impératifs | Appliquer, basculer ou réinitialiser en mémoire un patch de style visuel ou un `namedState`. |
| **`"setVisibility"`** | Impératif | Les 13 événements impératifs | Afficher, masquer, basculer ou réinitialiser la visibilité en mémoire. |
| **`"setState"`** | Impératif | Les 13 événements impératifs | Forcer, basculer ou réinitialiser `disabled` ou `readOnly` en mémoire. |
| **`"onTooltip"`** | Déclaratif | **Uniquement `"onHover"`** | Afficher une info-bulle statique ou liée à un repository au survol. |
| **`"bindState"`** | Réactif | **Uniquement `"onBinding"`** | Lier réactivement `invisible`, `readOnly` ou `disabled` à un booléen de repository. |
| **`"bindZoneSize"`** | Réactif | **Uniquement `"onBinding"`** | Lier et animer l'épaisseur d'un côté (`west`/`east`/`north`/`south`) d'un `SuperLayout`. |
| **`"addArrayItem"`** | Impératif | Les 13 événements impératifs | Créer et sélectionner une nouvelle ligne dans un tableau JSON (`jsonSchema` + `creationDefault`). |
| **`"removeArrayItem"`** | Impératif | Les 13 événements impératifs | Supprimer la ligne courante ou sélectionnée d'un tableau JSON (immédiat par défaut, `confirm: false`). |
| **`"creationDefault"`** | Déclaratif | **Uniquement `"onCreate"`** | Définir la valeur initiale d'un champ `SuperValue` lors d'une création de ligne. |
| **`"runJavaScript"`** | Impératif | Les 13 événements impératifs | Exécuter un script QuickJS contrôlé (`ctx.set`, `ctx.get`, `ctx.removeAt`, `ctx.select`). |
| **`"sortCollection"`** | **Hybride** | **`"onBinding"` OU les 13 événements impératifs** | Trier côté client un `SuperListView` ou `SuperTable` sans altérer le repository. |
| **`"filterCollection"`** | **Hybride** | **`"onBinding"` OU les 13 événements impératifs** | Filtrer côté client un `SuperListView` ou `SuperTable` via un `BehaviorValidator`. |
| **`"searchProvider"`** | Impératif | Les 13 événements impératifs | Exécuter un provider de recherche (`store.providers.search`). |
| **`"datasource"`** | Impératif | Les 13 événements impératifs | Exécuter une commande Search / Pagination / Tri / CRUD sur `store.datasources`. |

---

### 4.1. Navigation, Export PDF & Bus d'événements

#### 1. `"goToPage"` (`GoToPageAction`)
Pousse (`router.push`) une route du `pageCatalog` (y compris les pages modales `"pageType": "dialog" | "bottomSheet" | "sideSheet"` qui s'ouvrent par-dessus l'écran courant tout en partageant la sélection Maître / Détail des repositories !).
- `"pagePath"` *(requis, `string` ; alias `"path"` accepté)* : chemin de la page cible commençant par `"/"` (ex. `"/clients/edition"`).
- `"pageId"` *(optionnel, `string`)* : identifiant de la page dans `pageCatalog.pages`.
- `"pageName"` *(optionnel, `string`)* : libellé lisible de la page.

```json
{
  "type": "goToPage",
  "pagePath": "/devis/apercu-pdf",
  "pageId": "page-devis-a4",
  "pageName": "Aperçu Devis A4"
}
```

#### 2. `"generatePdf"` (`GeneratePdfAction`)
Génère un document PDF multi-feuilles via `A4PdfGenerator` à partir d'une page déclarée avec `"pageType": "a4Document"` dans `pageCatalog`.
- `"pageId"` *(optionnel, `string` non vide)* : ID de la page `"a4Document"`. Si omis, cible la page A4 englobante ou l'unique page A4 du catalogue.
- `"pageName"` *(optionnel, `string`)* : nom lisible de la page cible.
- `"fileName"` *(optionnel, `string` non vide)* : surcharge du nom de fichier `.pdf` (ex. `"Devis-Client.pdf"`).
- `"outputMode"` *(optionnel, défaut `"exportDialog"`)* :
  - `"exportDialog"` *(alias `"previewAndPrint"`)* : ouvre la boîte de dialogue d'export permettant de choisir le dossier, d'enregistrer et d'ouvrir le PDF ;
  - `"saveFile"` : enregistre directement dans le dossier `Downloads` / `Documents` de l'utilisateur avec notification `SnackBar`.

#### 3. `"emitEvent"` (`EmitEventAction`)
Publie un `SuperComponentEvent` sur le bus `SuperApp.eventBus` écouté par le code Dart de l'application hôte (`eventBus.on('<eventId>').listen(...)`).
- `"eventId"` *(requis, `string`)* : identifiant non vide **sans espaces en début ni fin** (ex. `"explorer.openItem"`).
- `"custom"` *(optionnel, `object`, défaut `{}`)* : charge utile JSON statique libre transmise telle quelle dans `event.custom` à côté des données automatiques `event.data`.

#### 4. `"goBack"` (`GoBackAction`)
Ferme la page modale courante (`dialog`, `bottomSheet`, `sideSheet`) ou revient à l'écran précédent dans la pile de navigation (`Navigator` puis `GoRouter`).
- `"fallbackPagePath"` *(optionnel, `string` non vide sans espaces superflus ; alias `"fallbackPath"` accepté)* : route absolue de secours (ex. `"/"` ou `"/accueil"`) si aucune vue ne peut être dépilée.

#### 5. `"showMessage"` (`ShowMessageAction`)
Affiche un retour visuel non bloquant (`SnackBar` Material 3). Très utile comme feedback de succès ou dans `elseAction` lorsque `validator` échoue !
- `"severity"` *(optionnel, défaut `"info"`)* : `"info"` | `"success"` | `"warning"` | `"error"`.
- `"message"` *(requis si `"binding"` est omis, sinon repli si la liaison est vide/nulle)* : texte affiché.
- `"binding"` *(optionnel)* : liaison réactive vers un message du repository.
- `"durationMs"` *(optionnel, `int > 0`, défaut `3000`)* : durée d'affichage en millisecondes.

#### 6. `"copyToClipboard"` (`CopyToClipboardAction`)
Copie une valeur textuelle dans le presse-papiers système (`Clipboard.setData`).
- **Source mutuellement exclusive (exactement 1 requise)** :
  - `"text"` *(chaîne non vide)* ;
  - `"targetComponentId"` *(ID d'un composant monté ou lié)* ;
  - `"binding"` *(liaison JSON résolue via `JsonListScope`)*.
- `"feedbackMessage"` *(optionnel, `string`)* : affiche une `SnackBar` de confirmation après la copie.

---

### 4.2. État visuel et interactif éphémère en mémoire (`BehaviorRuntimeStateController`)

Les trois actions `"setStyle"`, `"setVisibility"` et `"setState"` modifient l'apparence ou l'interactivité **exclusivement en mémoire** (`BehaviorRuntimeStateScope`), sans jamais écrire dans `Appearance` ni sur le disque.
- **Résolution intelligente de `"targetComponentId"`** :
  - Omis ou `null` $\rightarrow$ agit sur le composant déclencheur lui-même (dans sa ligne courante s'il est dans une collection).
  - Renseigné (`"targetComponentId": "<autreId>"`, sans espaces autour) $\rightarrow$ si le déclencheur est dans une ligne de liste/table/arbre et qu'`<autreId>` est monté **dans cette même ligne**, seule l'instance de cette ligne est modifiée ; sinon la surcharge s'applique globalement à `<autreId>`.
- **Priorité avec `"bindState"`** : une surcharge impérative (`setVisibility`, `setState`) prime sur l'état calculé par `bindState` tant qu'elle est active ; l'opération `"reset"` supprime la surcharge impérative et rend immédiatement la main à `bindState` (ou à la configuration statique).

#### 4. `"setStyle"` (`SetStyleAction` & `BehaviorStylePatch`)
- `"operation"` *(optionnel, défaut `"apply"`)* :
  - `"apply"` : fusionne les propriétés de `"style"` par-dessus les surcharges actives de la cible ;
  - `"toggle"` : si toutes les propriétés de `"style"` sont déjà actives avec les mêmes valeurs sur la cible, retire uniquement ces propriétés ; sinon les applique (idéal pour les boutons/chips filtres actifs !) ;
  - `"reset"` : efface toutes les surcharges de style runtime de la cible (`"style"` est alors omis).
- `"targetComponentId"` *(optionnel, `string` non vide sans espaces)* : autre composant ou surface cible.
- `"durationMs"` *(optionnel, `int >= 0`, défaut `0`)* : durée de transition animée en millisecondes.
- `"style"` *(requis et non vide sauf si `"operation": "reset"`)* : objet `BehaviorStylePatch` acceptant :
  - `"backgroundColor"` *(alias `"color"`)* : couleur `"theme:<rôle>"` ou `"#RRGGBB"` / `"#AARRGGBB"` ;
  - `"foregroundColor"` *(alias `"textColor"`)* : couleur du texte et de l'icône ;
  - `"borderColor"` : couleur de bordure ;
  - `"borderWidth"` (`number >= 0`), `"radius"` (`number >= 0`), `"opacity"` (`number` entre `0.0` et `1.0`), `"elevation"` (`number >= 0`) ;
  - `"fontSize"` (`number > 0`), `"fontWeight"` (`"light"`, `"normal"`, `"medium"`, `"semibold"`, `"bold"` ou `"w100"`..`"w900"`) ;
  - `"namedState"` (`string` non vide sans espaces) : active un état métier déclaré dans `states.named` du composant ou de la surface ;
  - `"fill"`, `"shadow"`, `"neon"` : objets identiques à ceux de `ContainerStyle`.

#### 5. `"setVisibility"` (`SetVisibilityAction`)
- **`"mode"`** *(**requis**, `string`)* : `"show"` | `"hide"` | `"toggle"` | `"reset"`. *(Attention : `"mode"` est obligatoire en JSON dans `setVisibility`.)*
- `"targetComponentId"` *(optionnel, `string` non vide sans espaces)*.
- `"maintainSize"` *(optionnel, `boolean`, défaut `false`)* : si `true` avec `"hide"` ou `"toggle"`, conserve l'espace géométrique du composant masqué dans son layout.

#### 6. `"setState"` (`SetStateAction`)
- **`"state"`** *(**requis**, `string`)* : `"disabled"` (bloque clics, focus, saisie et autres behaviors + active `AutomaticState.disabled`) | `"readOnly"` (verrouille l'édition de la valeur + active `AutomaticState.readOnly`).
- `"operation"` *(optionnel, défaut `"set"`)* : `"set"` | `"toggle"` | `"reset"`.
- `"value"` *(optionnel, `boolean`, défaut `true`, pertinent uniquement avec `"operation": "set"`)* : `true` active l'état (`disabled` ou `readOnly`), `false` réactive / rend modifiable.
- `"targetComponentId"` *(optionnel, `string` non vide sans espaces)*.

---

### 4.3. Actions déclaratives et liaisons réactives (`onHover`, `onBinding`, `onCreate`)

#### 7. `"onTooltip"` (`TooltipAction` — exige `"event": "onHover"`)
Disponible sur **tout ID de composant** (bouton, icône, champ, carte, ligne `<listId>:item`, onglet, layout).
- `"message"` *(requis et non vide si `"binding"` est absent)* : texte fixe de l'info-bulle.
- `"binding"` *(optionnel)* : liaison vers un attribut texte ou `@calcul` (ex. `"clients[?].commentaire"` dans `<listId>:item`, ou `"crm:aide.bandeau"`).
- **Règle importante** : lorsque `"binding"` est renseigné, `"message"` **ne sert pas de fallback** ; si la valeur liée est `null`, `""` ou qu'aucune ligne n'est sélectionnée, aucune info-bulle ne s'affiche.

#### 8. `"bindState"` (`StateBindingAction` — exige `"event": "onBinding"`)
Observe en continu un attribut booléen (ou `@calcul` booléen) d'un repository et applique automatiquement l'état au composant (et à ses descendants via `ComponentBehaviorStateScope`).
- **`"state"`** *(**requis**)* : `"invisible"` | `"readOnly"` | `"disabled"`.
- **`"binding"`** *(**requis**)* : liaison vers un booléen (`true`/`false` ou chaînes `"true"`/`"false"`/`"1"`/`"0"`/`"yes"`/`"no"`/`"oui"`/`"non"` ; toute autre chaîne ou nombre non booléen signale une erreur de liaison ; `null` ou absence de sélection désactive l'état).
- `"whenValue"` *(optionnel, `boolean`, défaut `true`)* : mettre `false` pour appliquer l'état lorsque le booléen vaut `false` (ex. `"state": "disabled", "whenValue": false` sur `"estModifiable"`).
- `"maintainSize"` *(optionnel, `boolean`, défaut `false`, uniquement pour `"state": "invisible"`)* : conserve la place dans le layout.

#### 9. `"bindZoneSize"` (`ZoneSizeBindingAction` — exige `"event": "onBinding"` sur un `SuperLayout`)
Lie l'épaisseur d'un volet latéral ou horizontal d'un `SuperLayout` à un attribut numérique d'un repository et anime toute transition (tiroir rétractable piloté par les données).
- **`"zone"`** *(**requis**)* : **uniquement un côté** parmi `"west"` | `"east"` | `"north"` | `"south"` (**jamais `"center"`** !). Le côté correspondant doit être activé (`"west": true`, etc.) sur le `SuperLayoutConfig`.
- **`"binding"`** *(**requis**)* : liaison vers un nombre (`<= 0` referme entièrement la zone à `0px` ; `null` restaure la taille statique configurée sur le layout).
- `"unit"` *(optionnel, défaut `"pixels"`)* : **`"pixels"`** ou **`"percent"`** *(attention : écrire `"pixels"` ou `"percent"` en toutes lettres dans `bindZoneSize`, pas `"px"` ni `"%"`)*.
- `"durationMs"` *(optionnel, `int >= 0`, défaut `250`)* : durée de l'animation en millisecondes (`0` = instantané ; l'affichage initial s'applique sans animation).
- `"curve"` *(optionnel, défaut `"easeInOut"`)* : `"linear"` | `"easeIn"` | `"easeOut"` | `"easeInOut"` | `"fastOutSlowIn"` | `"easeOutBack"`.

---

### 4.4. Création de lignes JSON Schema & Scripts contrôlés QuickJS

#### 10. `"addArrayItem"`, `"removeArrayItem"` & 11. `"creationDefault"`
Permettent d'ajouter ou de supprimer proprement une entité dans un tableau JSON (racine comme `"crm:clients"` ou imbriqué Maître/Esclave comme `"crm:clients[?].commandes"`) depuis n'importe quel bouton d'action :

- **`"addArrayItem"`** (impératif, typiquement sur `"event": "onTap"` d'un bouton « Nouveau client ») :
  - **`"binding"`** *(**requis**)* : chemin du tableau cible (ne peut jamais cibler un `@calcul`).
  - `"selectCreated"` *(optionnel, `boolean`, défaut `true`)* : sélectionne immédiatement la ligne créée dans `JsonArrayBinding`, ce qui met à jour instantanément la fiche Maître / Détail ou le formulaire d'édition !
- **`"removeArrayItem"`** (`RemoveArrayItemAction`, impératif) : supprime l'élément courant (dans une ligne `JsonListScope`) ou sélectionné (Maître/Détail) dans le tableau cible :
  - **`"binding"`** *(**requis**)* : chemin du tableau (`"crm:clients"`, `"clients[?].commandes"`) ou de l'élément (`"crm:clients[?]"`). Interdit sur `@...`.
  - `"confirm"` *(optionnel, `boolean`, **défaut `false`**)* : suppression immédiate par défaut ; passer `true` pour demander confirmation via un dialogue modal (`"confirmTitle"`, `"confirmMessage"` optionnels).
  - `"selectAdjacent"` *(optionnel, `boolean`, défaut `true`)* : repositionne la sélection sur la ligne voisine (ou vide la sélection si le tableau devient vide).
- **`"creationDefault"`** (déclaratif, **exige `"event": "onCreate"`** sur un composant `SuperValue`) :
  - **`"defaultValue"`** : valeur JSON initiale (`string`, `number`, `boolean`, `list`, `map` ou `null`) injectée dans le champ lié lors de la création d'une ligne.
  - `"binding"` *(optionnel)* : omis par défaut (utilise automatiquement le `SuperValueConfig.binding` du champ porteur, y compris avec héritage de repository dans un template de liste).

- **Pipeline exact de construction de la nouvelle ligne (`RepositoryArrayCreationService`)** :
  1. Si le repository possède un `jsonSchema` décrivant les `items` du tableau, `JsonSchemaFieldResolver.buildDefaultArrayItem` génère un objet conforme au schéma (`default`, premier `enum`, valeurs neutres par `type`) ;
  2. Sinon, le moteur clone à blanc le dernier élément existant via `JsonRepositoryStore.blank(items.last)` (ou `{}` si le tableau est vide) ;
  3. Puis il écrase chaque champ disposant d'un comportement `"creationDefault"` actif (`enabled: true`) ciblant ce tableau dans l'`Appearance` ;
  4. Enfin, il valide le document résultant contre le `jsonSchema` et sélectionne le nouvel indice si `selectCreated: true`.

```json
{
  "behaviors": {
    "btn-new-task": [
      {
        "id": "b-add-task",
        "event": "onTap",
        "action": {
          "type": "addArrayItem",
          "binding": "suivi_projet:taches",
          "selectCreated": true
        }
      }
    ],
    "field-task-statut": [
      {
        "id": "b-default-statut",
        "event": "onCreate",
        "action": {
          "type": "creationDefault",
          "defaultValue": "a_faire"
        }
      }
    ],
    "field-task-priorite": [
      {
        "id": "b-default-priorite",
        "event": "onCreate",
        "action": {
          "type": "creationDefault",
          "defaultValue": "normale"
        }
      }
    ]
  }
}
```

#### 12. `"runJavaScript"` (`RunJavaScriptAction` — mutations atomiques QuickJS)
Exécute un script JavaScript synchrone dans le moteur embarqué QuickJS pour effectuer des transitions métier, incrémenter des compteurs, réinitialiser des filtres, calculer/copier des valeurs ou supprimer/réordonner des éléments d'un tableau source.

- **`"code"`** *(**requis**, `string` non vide)* : corps d'une fonction exécutée en `"use strict"`.
- `"repositoryId"` *(optionnel dans une collection où il hérite du `JsonListScope` ; **requis hors collection**, `^[a-z0-9_]{1,32}$` ou ID 32 hex ou alias du tour courant)*.

> **Contrat strict de l'environnement QuickJS de `"runJavaScript"` (différent de `calculatedAttributes` !)** :
> - **Signature reçue par `"runJavaScript"` : `(ctx, doc, event)`** :
>   - **`doc`** : `Proxy` profond **en lecture seule** sur le document racine complet du repository ciblé (ex. `doc.clients`, `doc.ui.westWidth`). Toute tentative de mutation directe (`doc.ui.westWidth = 0` ou `doc.clients.push(...)`) lève immédiatement une `TypeError` !
>   - **`event`** : `Proxy` **en lecture seule** contenant `event.componentId`, `event.componentType`, `event.event` (nom canonique, ex. `"onTap"`), `event.trigger` et `event.data` (ex. `event.data.value`, `event.data.index`).
>   - **`ctx.repositoryId`** : identifiant du repository ciblé.
>   - **`ctx.get(path, repositoryId?, defaultValue?)`** *(+ `getString`, `getNum`, `getInt`, `getDouble`, `getBool`, `getList`, `getObject`)* : lecture seule sur le repository courant ou un **autre repository** du store (y compris ses attributs calculés `@...`).
>   - **`ctx.set(path, value)`** : écrit une valeur JSON sur `path` dans le repository ciblé (nombres finis uniquement, pas de `NaN`/`Infinity`/`Function`/`Promise`).
>   - **`ctx.removeAt(arrayPath, index)`** / **`ctx.remove(path)`** : supprime un élément d'un tableau source (`arrayPath` + indice, ou `path` avec `[?]` / `[index]`), en rejetant tout chemin `@...`.
>   - **`ctx.select(arrayPath, index, repositoryId?)`** : met à jour la sélection Maître / Détail dans `JsonArrayBinding` après la transaction.
> - **Attention — Ne confonds JAMAIS les deux signatures QuickJS** :
>   - Dans `"repositories.*.calculatedAttributes"`, la formule reçoit `(row, ctx, doc)` avec `ctx.get(...)` et **aucun** `ctx.set`.
>   - Dans `"behaviors.*.action"` (`"runJavaScript"`), le script reçoit **`(ctx, doc, event)`** : **`row` n'existe pas** dans `runJavaScript` (lis via `doc`, `event.data` ou `ctx.get(...)`, et écris via `ctx.set` / `ctx.removeAt` / `ctx.select`).
> - **Support des jokers `[?]` dans `ctx.set`** :
>   - `ctx.set("clients[?].statut", "valide")` résout automatiquement `[?]` avec l'indice de la ligne englobante (si le bouton est dans `<listId>:item` ou le template de la liste) **ou** avec la ligne actuellement sélectionnée dans le `JsonArrayBinding` Maître / Détail (si le bouton est dans la fiche détail en zone `center` !).
> - **Atomicité, Compare-And-Swap & Validation Schema** :
>   - Toutes les écritures `ctx.set(...)` d'une même exécution sont groupées et appliquées **en une seule transaction atomique** vérifiant que le document n'a pas divergé (`JsonRepositoryConflictException`) et validant le résultat complet contre le `jsonSchema` du repository.
>   - Aucune fonction asynchrone (`async`/`await`/`Promise`) n'est exécutée.
>   - Tout chemin contenant un segment `@...` est formellement rejeté (`FormatException`).

```json
{
  "id": "b-approve-quote",
  "event": "onTap",
  "validator": {
    "type": "bindingEquals",
    "binding": "crm_clients:clients[?].statut",
    "value": "en_attente"
  },
  "action": {
    "type": "runJavaScript",
    "repositoryId": "crm_clients",
    "code": "ctx.set('clients[?].statut', 'actif'); ctx.set('ui.lastApprovedAt', '2026-11-22');"
  }
}
```

---

### 4.5. Tri et Filtrage côté client des Collections (`CollectionViewTransform`, `"sortCollection"` & `"filterCollection"`)

Le service `CollectionViewTransform` (piloté par `CollectionViewTransformController` et `CollectionViewStateRegistry`) fournit aux composants **`SuperListView`** et **`SuperTable`** un moteur unifié de filtrage et de tri en mémoire côté client :

- **Zéro mutation du repository (`visibleSourceIndices`)** : le moteur ne réécrit jamais le tableau dans `JsonRepositoryStore`. Il calcule une table d'indices sources visibles (`visualIndex -> sourceIndex`). Ainsi, **la sélection Maître / Détail (`JsonArrayBinding`), l'édition en place des `SuperValue`, les scripts `ctx.set("items[?].x", ...)` et le bouton de suppression `allowRemove` agissent toujours sur le véritable élément source** sans décalage d'indice !
- **Réactivité automatique sans câblage superflu (`collectDependencies`)** : lorsqu'un `filterCollection` ou `sortCollection` référence un autre composant (`targetComponentId` ou `expectedComponentId`, par exemple un champ `SuperValue` de recherche **même sans `binding` de repository**), `CollectionViewTransformController` s'abonne automatiquement à `ComponentRuntimeValueRegistry` et recalcule instantanément la vue à chaque frappe clavier !
- **Suspension automatique en mode édition** : en mode édition visuelle, toutes les lignes restent affichées dans leur ordre source.

#### Architecture à deux modes : Déclaratif (`"onBinding"`) vs Impératif (`onTap`, `onChanged`, …)

| Aspect | Mode Déclaratif (`"event": "onBinding"`) | Mode Impératif (`"onTap"`, `"onChanged"`, `"onSubmitted"`, …) |
| :--- | :--- | :--- |
| **Où attacher le behavior ?** | **Directement sur l'ID de la `SuperListView` ou `SuperTable`** (`behaviors["list-clients"]`). | Sur **n'importe quel composant** (bouton de tri, chip de filtre, bouton « Réinitialiser », champ) ou sur la collection. |
| **`targetComponentId`** | **Interdit** (`FormatException` si renseigné). | **Requis** si attaché hors de la collection (ID du `SuperListView` ou `SuperTable` cible) ; omis si attaché à la collection elle-même. |
| **Modes `sortCollection`** | `"set"` (défaut) ou `"add"`. **`"clear"` et `"direction": "toggle"` sont interdits**. | `"set"` (défaut), `"add"` (tri multi-colonnes) ou **`"clear"`**, avec support de **`"direction": "toggle"`** (alterne `asc` $\leftrightarrow$ `desc`). |
| **Modes `filterCollection`** | **Uniquement `"apply"`** (défaut). | `"apply"` (défaut), **`"toggle"`** (active/désactive sur clic de chip), **`"clear"`** (retire `filterKey`) ou **`"clearAll"`** (retire tous les filtres impératifs). |
| **Combinaison runtime** | Les filtres déclaratifs actifs et **tous** les filtres impératifs actifs (`filterKey`) se **cumulent en ET logique**. Pour le tri, un tri impératif actif **prime** sur le tri déclaratif ; `"mode": "clear"` efface le tri impératif et restaure le tri déclaratif (ou l'ordre source). |

#### 13. `"sortCollection"` (`SortCollectionAction`)

- `"mode"` *(optionnel, défaut `"set"`)* :
  - `"set"` : remplace les critères de tri actifs ;
  - `"add"` : ajoute un critère secondaire (ou met à jour le sens si ce `path` figure déjà dans les critères actifs) ;
  - `"clear"` *(impératif uniquement)* : supprime le tri impératif actif (`criteria` doit alors être absent/vide).
- `"targetComponentId"` *(impératif uniquement, `string` non vide ; alias `"targetId"` accepté)*.
- **Critères de tri** — deux syntaxes équivalentes (en mono-critère `mode: "set"`, préfère la forme compacte directe) :
  1. **Raccourci mono-critère directement sur l'action** :
     ```json
     {
       "type": "sortCollection",
       "targetComponentId": "table-clients",
       "path": "caAnnuel",
       "direction": "toggle"
     }
     ```
  2. **Liste multi-critères `"criteria"`** (tri stable dans l'ordre des critères, puis par indice source d'origine) :
     ```json
     {
       "type": "sortCollection",
       "criteria": [
         { "path": "statut", "direction": "asc" },
         { "path": "caAnnuel", "direction": "desc", "nullsLast": true }
       ]
     }
     ```
- **Propriétés d'un critère (`CollectionSortCriterion`)** :
  - **`"path"`** *(requis, alias `"field"`)* : chemin relatif à la ligne (`"nom"`, `"adresse.ville"`), chemin modèle (`"clients[?].nom"`), attribut calculé par ligne avec son préfixe modèle (**`"clients[?].@montantHt"`** — requis pour qu'un `@calcul` par ligne soit résolu dans le `JsonListScope` de chaque ligne), ou `"."` pour un tableau de valeurs primitives (`["Paris", "Lyon"]`).
  - `"direction"` *(optionnel, défaut `"asc"`)* : `"asc"` | `"desc"` | `"toggle"` *(impératif uniquement : premier clic $\rightarrow$ `"asc"`, clic suivant sur le même champ $\rightarrow$ `"desc"`)*.
  - `"caseSensitive"` *(optionnel, `boolean`, **défaut `false`**)* : tri alphabétique insensible à la casse par défaut.
  - `"nullsLast"` *(optionnel, `boolean`, **défaut `true`**)* : place `null` / valeurs absentes à la fin quel que soit le sens `asc` ou `desc`.
- **Comparateur intelligent (`CollectionViewTransform.compareValues`)** : compare nativement les nombres (`num`), les booléens (`false < true`), les **dates ISO 8601** (`"2026-05-19"` / `"2026-05-19T14:30:00Z"` comparées chronologiquement via `DateTime`), les couples nombre/chaîne numérique, et les chaînes.
- **Tri déclaratif piloté par un sélecteur (`onBinding` + `validator`)** : sur une collection, `behavior.validator` sert de **condition d'activation** du `sortCollection`. Tu peux ainsi attacher plusieurs `sortCollection` en `onBinding` gardés chacun par `{"type": "otherEquals", "targetComponentId": "select-tri", "value": "ca_desc"}` !

#### 14. `"filterCollection"` (`FilterCollectionAction`)

- `"mode"` *(optionnel, défaut `"apply"`)* :
  - `"apply"` : applique ou remplace le filtre identifié par `filterKey` ;
  - `"toggle"` *(impératif uniquement)* : active ce prédicat sur `filterKey` s'il n'y est pas déjà, ou le retire s'il est déjà identique (parfait pour un bouton/chip filtre à bascule !) ;
  - `"clear"` *(impératif uniquement, `predicate` interdit)* : retire uniquement le filtre portant la clé `filterKey` ;
  - `"clearAll"` *(impératif uniquement, `predicate` et `filterKey` interdits)* : retire tous les filtres impératifs actifs de la collection.
- `"targetComponentId"` *(impératif uniquement, `string` non vide ; interdit avec `"onBinding"`)*.
- `"filterKey"` *(impératif uniquement, `string` non vide ; défaut = ID du composant déclencheur)* : identifie un emplacement de filtre indépendant. Exemple : utiliser `"filterKey": "statut"` sur 3 boutons « Actifs », « En attente », « Bloqués » permet à un clic sur « En attente » de remplacer le filtre `"statut"` tout en conservant un filtre `"priorite"` actif par ailleurs !
- `"predicate"` (`BehaviorValidator`) : prédicat évalué **pour chaque ligne** avec son `JsonListScope` et son `rowItem` en mémoire.
  - Dans `"predicate"`, tu peux écrire des liaisons courtes relatives à la ligne (`"binding": "nom"` ou `"binding": "clients[?].nom"`, sans `repositoryId`).

> **Règle d'or du rôle dual `validator` + `predicate` en mode `"onBinding"`** :
> Sur un comportement `filterCollection` attaché avec `"event": "onBinding"` à une `SuperListView` ou `SuperTable` :
> 1. **Barre de recherche réactive (Pattern recommandé : `validator` + `predicate`)** :
>    - Renseigne **`validator`** comme **garde d'activation globale** (ex. `{"type": "otherIsFill", "targetComponentId": "input-search"}`) ;
>    - Renseigne **`predicate`** comme **filtre par ligne** (ex. `{"type": "bindingContains", "binding": "clients[?].nom", "expectedComponentId": "input-search", "caseSensitive": false}`).
>    - Résultat : tant que `"input-search"` est vide, `validator` vaut `false` $\rightarrow$ le filtre est court-circuité en $O(1)$ et toutes les lignes s'affichent ; dès que l'utilisateur tape un caractère, `validator` passe à `true` et `predicate` filtre instantanément chaque ligne !
> 2. **Filtre permanent sans garde (`predicate` seul, ou `validator` seul sans `predicate`)** :
>    - Si `predicate` est fourni sans `validator`, `predicate` filtre chaque ligne en permanence.
>    - Si `predicate` est omis et `validator` est fourni, `validator` est lui-même évalué par ligne.

---

### 4.6. Providers de recherche & Datasources Search / Pagination / CRUD

> **Vérification préalable obligatoire** : n'invente **jamais** un `providerId` ou un `datasourceId` inexistant. En Chat Vibe, appelle d'abord l'outil d'inspection `get_datasources_and_providers` (ou vérifie l'`ÉTAT ACTUEL`) pour connaître les identifiants réellement enregistrés dans `store.providers` et `store.datasources`. Pour des données purement locales dans un repository JSON, utilise plutôt `"filterCollection"`, `"sortCollection"`, `"addArrayItem"` et `"runJavaScript"`.

#### 15. `"searchProvider"` (`SearchProviderAction`)
Exécute `store.providers.search(providerId)` (lit le repository de filtre du provider, appelle l'API HTTP ou le callback hôte, et écrit les résultats dans son repository cible).
- **`"providerId"`** *(**requis**, `^[a-z0-9_]{1,32}$`)* : seule clé autorisée avec `"type"` (toute clé supplémentaire lève `FormatException`).

#### 16. `"datasource"` (`DatasourceAction`)
Exécute `store.datasources.run(datasourceId, command, scope: ...)` en transmettant automatiquement le contexte de ligne courant (`JsonListScope` ou sélection Maître / Détail) pour les opérations par entité.
- **`"datasourceId"`** *(**requis**, `^[a-z0-9_]{1,32}$`)*.
- `"command"` *(optionnel, défaut `"search"`)* parmi les **11 commandes** :
  - Recherche & pagination : `"search"` (depuis la 1re page), `"refresh"` (page courante), `"firstPage"`, `"previousPage"`, `"nextPage"`, `"loadMore"` (concatène la page suivante), `"sort"` ;
  - Opérations CRUD d'entité (avec synchronisation locale automatique de la liste et du détail) : `"create"`, `"read"`, `"update"`, `"delete"`.
- `"field"` *(**requis si et seulement si `"command": "sort"`**, **interdit** pour toutes les autres commandes)* : nom du champ serveur à trier.
- `"direction"` *(optionnel, `"asc"` | `"desc"`, **autorisé uniquement si `"command": "sort"`**)* : omis = inverse automatiquement le sens à chaque nouveau clic sur le même champ.

---

## 5. Arbre de décision IA : choisir le bon mécanisme sans sur-ingénierie

| Besoin fonctionnel ou UX | Mécanisme GenUI à utiliser en priorité | À éviter |
| :--- | :--- | :--- |
| Effet visuel au survol ou à la sélection d'une carte / d'un bouton | `styles[id].hoverEffect`, `states.hover`, `states.selected`, `automatic.contentHover` | `setStyle` sur `onHoverEnter` / `onHoverExit` pour un simple hover CSS |
| Couleur, badge ou icône variant selon un statut métier (`"paye"`, `"retard"`, `"brouillon"`) | `states.named` + `states.binding` (sur `SuperValue`, `SuperAction`, `SuperIndicator` ou `ContainerStyle`) | `runJavaScript` ou `setStyle` impératif |
| Afficher des sous-arbres de composants différents selon un type ou statut | Composant `"type": "conditional"` (`SuperConditional` avec branches `"case:<valeur>"` et `"default"`) | Empiler plusieurs `bindState` `"invisible"` contradictoires |
| Masquer, griser (`disabled`) ou verrouiller (`readOnly`) un champ selon un booléen du repository | Behavior **`"bindState"`** (`"event": "onBinding"`) | Script JS tentant de modifier l'IHM |
| Ouvrir / fermer un tiroir, panneau de filtres ou aperçu purement local à l'écran | Behavior **`"setVisibility"`** (`"mode": "toggle"`) ou **`"bindZoneSize"`** (`"event": "onBinding"` pour animer un côté `west`/`east`) | Créer une deuxième page dupliquée |
| Recherche instantanée, tri par colonne et chips de filtre sur un tableau JSON en mémoire | Behaviors **`"filterCollection"`** + **`"sortCollection"`** (`CollectionViewTransform`) | Écraser le tableau du repository avec un sous-tableau filtré via `runJavaScript` (détruirait les autres lignes !) |
| Total, sous-total, marge, compteur ou KPI dérivé des données | Attribut calculé **`"calculatedAttributes"`** (`@montantHt`, `@totalGlobal`) lié en `mode: "display"` | Recalculer et stocker le total via `runJavaScript` sur chaque `onChanged` |
| Ajouter une ligne vierge pré-initialisée dans un tableau JSON | **`"addArrayItem"`** sur un bouton `+` (ou `"allowAdd": true` sur `SuperListView`) + **`"creationDefault"`** (`"onCreate"`) | Forger l'objet à la main en JS sans respecter le `jsonSchema` |
| Action métier atomique (changer un statut, archiver, dupliquer, remettre à zéro des filtres stockés) | Behavior **`"runJavaScript"`** utilisant `ctx.set(...)` (éventuellement précédé d'un `validator` `"all"` / `"otherIsValid"`) | `emitEvent` sans écouteur hôte |
| Appel API distant paginé ou CRUD serveur | **`"datasource"`** ou **`"searchProvider"`** (après vérification via `get_datasources_and_providers`) | Inventer un `datasourceId` inexistant |

---

## 6. Checklist anti-`FormatException` (les 12 pièges classiques à éviter)

1. **`"onHover"` vs `"onHoverEnter"`** : n'associe **jamais** `"onHover"` à autre chose que `"onTooltip"`. Pour déclencher une action impérative quand la souris entre/sort, utilise `"onHoverEnter"` / `"onHoverExit"`.
2. **`"onBinding"` restreint à 4 actions** : seuls `"bindState"`, `"bindZoneSize"`, `"sortCollection"` et `"filterCollection"` acceptent `"event": "onBinding"`.
3. **`"not"` prend `"validator"` (singulier), `"all"` / `"any"` prennent `"validators"` (pluriel)** : inverser les deux lève immédiatement une `FormatException`.
4. **Casse des validateurs de recherche** : `ValueBehaviorValidator.caseSensitive` vaut `true` par défaut $\rightarrow$ mets toujours `"caseSensitive": false` sur `"bindingContains"` / `"bindingStartsWith"` lorsqu'ils sont reliés à une saisie utilisateur.
5. **Pas de `isEmpty` / `isFill` sur un booléen ou le nombre `0`** : `0` et `false` sont considérés **remplis** (`isFill == true`). Utilise `"isTrue"` / `"isFalse"` pour les booléens et `"greaterThan"` / `"greaterOrEqual"` pour tester un nombre.
6. **Pas de `isValid` / `isInvalid` sur une liaison brute** : `"bindingIsValid"` n'existe pas ; teste la validité sur un composant (`"isValid"`) ou sur un champ/conteneur (`"otherIsValid"` avec `"targetComponentId"`).
7. **Exclusivité de la cible de comparaison** : ne fournis jamais simultanément `"value"` et `"expectedComponentId"` (ni `"expectedBinding"`), et n'ajoute jamais `"expectedComponentId"` sur un opérateur unaire (`isFill`, `isEmpty`, `isTrue`, `isValid`…).
8. **Interdictions en mode `"onBinding"` sur les collections** : sur `sortCollection` et `filterCollection` avec `"event": "onBinding"`, ne mets **jamais** `"targetComponentId"`, ni `"mode": "clear"` / `"toggle"` / `"clearAll"`, ni `"direction": "toggle"`.
9. **`"mode"` obligatoire dans `"setVisibility"` et `"state"` obligatoire dans `"setState"`** : fournis toujours explicitement `"mode": "show" | "hide" | "toggle" | "reset"` pour `setVisibility`, et `"state": "disabled" | "readOnly"` pour `setState`.
10. **Unités de `"bindZoneSize"`** : écris `"unit": "pixels"` ou `"unit": "percent"` (jamais `"px"` ni `"%"`), et cible uniquement `"west"`, `"east"`, `"north"` ou `"south"` (jamais `"center"`).
11. **Signature QuickJS de `"runJavaScript"`** : utilise exclusivement `(ctx, doc, event)` avec `ctx.get(...)`, `ctx.set(...)`, `ctx.removeAt(...)` et `ctx.select(...)` ; n'utilise jamais `row`, `doc.x = ...`, `async`/`await`, ni d'écriture sur un chemin `@`.
12. **`elseAction` exige `validator`** : ne définis jamais `"elseAction"` sans `"validator"` ni sur un événement déclaratif (`onHover`, `onBinding`, `onCreate`).
13. **Préservation des behaviors existants lors d'un patch Vibe** : `behaviors["<id>"]` remplace toute la liste de `<id>` ; relis toujours `behaviors["<id>"]` dans l'état courant avant d'y ajouter une entrée.

---

## 7. Recette complète de référence (`"repositories"` + `"vibe"` interactif)

L'exemple ci-dessous constitue une réponse complète du Chat Vibe directement exécutable par `VibeRepositoryTurnTransaction` puis `AppearanceTransfer.applyVibe`. Il illustre de bout en bout :
- **Recherche temps réel multi-champs** (`filterCollection` en `onBinding` sur `"list-dossiers"` avec garde `otherIsFill("input-search")` + prédicat `any` insensible à la casse sur `client` et `reference`) ;
- **Chip de filtre à bascule + retour visuel** (`filterCollection` en `mode: "toggle"` avec `filterKey: "statut"` combiné à `setStyle` en `operation: "toggle"`) et bouton **Tout afficher** (`filterCollection` `mode: "clearAll"` + `sortCollection` `mode: "clear"` + `setStyle` `operation: "reset"`) ;
- **Tri interactif alterné** (`sortCollection` avec `direction: "toggle"` sur un attribut calculé `@montantTtc`) ;
- **Création de ligne pilotée par JSON Schema + valeurs par défaut** (`addArrayItem` + `creationDefault` sur `onCreate`) ;
- **Action métier QuickJS gardée par un validateur composite `all`** (`otherIsValid` + `bindingNotEquals` $\rightarrow$ `runJavaScript` via `ctx.set('dossiers[?].statut', 'valide')` et `ctx.set('dossiers[?].verrouille', true)`) ;
- **Réactivité d'état et d'interface** (`bindState` `readOnly` et `disabled` quand `dossiers[?].verrouille` est vrai, `bindZoneSize` animant le volet `west`, et `onTooltip` lié sur chaque ligne `list-dossiers:item`).

```json
{
  "message": "Mise en place de l'espace de pilotage des dossiers avec recherche instantanée, filtres combinables, tri sur montant TTC calculé, ajout guidé et validation verrouillée.",
  "repositories": {
    "pilotage_dossiers": {
      "name": "Pilotage Dossiers",
      "mode": "merge",
      "jsonSchema": {
        "type": "object",
        "required": ["ui", "dossiers"],
        "properties": {
          "ui": {
            "type": "object",
            "properties": {
              "westWidth": { "type": "number", "minimum": 0 }
            }
          },
          "dossiers": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["reference", "client", "statut", "montantHt", "tauxTva", "echeance", "verrouille"],
              "properties": {
                "reference": { "type": "string", "minLength": 3 },
                "client": { "type": "string", "minLength": 2 },
                "statut": { "type": "string", "enum": ["brouillon", "en_revue", "valide"] },
                "montantHt": { "type": "number", "minimum": 0 },
                "tauxTva": { "type": "number", "minimum": 0, "maximum": 1 },
                "echeance": { "type": "string", "format": "date" },
                "notes": { "type": "string" },
                "verrouille": { "type": "boolean" }
              }
            }
          }
        }
      },
      "calculatedAttributes": [
        {
          "name": "montantTtc",
          "scope": "dossiers[?]",
          "code": "Math.round((row.montantHt ?? 0) * (1 + (row.tauxTva ?? 0.2)) * 100) / 100",
          "description": "Montant TTC calculé par dossier"
        }
      ],
      "data": {
        "ui": {
          "westWidth": 360
        },
        "dossiers": [
          {
            "reference": "DOS-2026-101",
            "client": "Atelier Lumière",
            "statut": "en_revue",
            "montantHt": 12500,
            "tauxTva": 0.2,
            "echeance": "2026-12-05",
            "notes": "En attente de validation direction financière",
            "verrouille": false
          },
          {
            "reference": "DOS-2026-102",
            "client": "Boréal Logistique",
            "statut": "valide",
            "montantHt": 28400,
            "tauxTva": 0.2,
            "echeance": "2026-11-28",
            "notes": "Contrat signé et archivé",
            "verrouille": true
          },
          {
            "reference": "DOS-2026-103",
            "client": "Solstice Ingénierie",
            "statut": "brouillon",
            "montantHt": 6800,
            "tauxTva": 0.2,
            "echeance": "2026-12-18",
            "notes": "Chiffrage complémentaire à finaliser",
            "verrouille": false
          }
        ]
      }
    }
  },
  "vibe": {
    "mode": "light",
    "accent": "#3B5BDB",
    "styles": {
      "background": {
        "color": "theme:surfaceContainerLowest",
        "padding": 0
      },
      "list-dossiers:item": {
        "color": "theme:surface",
        "borderColor": "theme:outlineVariant",
        "borderWidth": 1,
        "radius": 12,
        "paddingInsets": [12, 38, 12, 14],
        "states": {
          "named": {},
          "hover": {
            "properties": ["background", "border"],
            "style": {
              "color": "theme:surfaceContainerLow",
              "borderColor": "theme:outline",
              "borderWidth": 1
            }
          },
          "selected": {
            "properties": ["background", "border"],
            "style": {
              "color": "theme:secondaryContainer",
              "borderColor": "theme:primary",
              "borderWidth": 1.5
            }
          }
        }
      },
      "card-detail": {
        "color": "theme:surface",
        "borderColor": "theme:outlineVariant",
        "borderWidth": 1,
        "radius": 16,
        "paddingInsets": [24, 24, 24, 24]
      }
    },
    "components": {
      "root": {
        "type": "native",
        "regions": { "appBar": true, "body": true },
        "placements": {
          "appBar": ["app-bar"],
          "body": ["scaffold:body"]
        },
        "slotTypes": {
          "app-bar": "registry:ApplicationBar",
          "scaffold:body": "scaffold:body"
        },
        "slotLabels": {
          "app-bar": "Barre supérieure",
          "scaffold:body": "Corps principal"
        }
      },
      "app-bar": {
        "type": "native",
        "regions": { "title": true, "actions": true },
        "placements": {
          "title": ["title-app"],
          "actions": ["btn-toggle-sidebar", "btn-add-dossier"]
        },
        "slotTypes": {
          "title-app": "registry:Value",
          "btn-toggle-sidebar": "registry:Action",
          "btn-add-dossier": "registry:Action"
        },
        "slotLabels": {
          "title-app": "Titre de la page",
          "btn-toggle-sidebar": "Bouton afficher ou masquer la liste",
          "btn-add-dossier": "Bouton nouveau dossier"
        },
        "actionsPadding": 12
      },
      "title-app": {
        "type": "value",
        "text": "Pilotage des dossiers",
        "fontSize": 18,
        "fontWeight": "semibold",
        "color": "theme:onSurface"
      },
      "btn-toggle-sidebar": {
        "type": "action",
        "kind": "icon",
        "variant": "text",
        "icon": "menu_open",
        "label": "Panneau latéral"
      },
      "btn-add-dossier": {
        "type": "action",
        "kind": "textAndIcon",
        "variant": "filled",
        "icon": "add",
        "label": "Nouveau dossier"
      },
      "mainLayout": {
        "type": "layout",
        "west": true,
        "westSize": 360,
        "autoSides": [],
        "zoneAxes": {
          "west": "column",
          "center": "column"
        },
        "zoneFlows": {
          "west": {
            "paddingInsets": [16, 12, 16, 16],
            "spacing": 12,
            "crossAxisAlignment": "stretch",
            "expandSlots": false
          },
          "center": {
            "paddingInsets": [16, 16, 16, 12],
            "spacing": 16,
            "crossAxisAlignment": "stretch",
            "expandSlots": true
          }
        },
        "placements": {
          "west": ["toolbar-filters", "list-dossiers"],
          "center": ["card-detail"]
        },
        "slotTypes": {
          "toolbar-filters": "registry:Layout",
          "list-dossiers": "registry:ListView",
          "card-detail": "registry:IterableContent"
        },
        "slotLabels": {
          "toolbar-filters": "Barre de recherche et filtres rapides",
          "list-dossiers": "Liste des dossiers",
          "card-detail": "Carte détail du dossier sélectionné"
        },
        "slotSizeConstraints": {
          "list-dossiers": {
            "preferredHeight": "420px",
            "fitContent": false
          }
        }
      },
      "toolbar-filters": {
        "type": "layout",
        "zoneAxes": {
          "north": "column",
          "center": "row"
        },
        "north": true,
        "autoSides": ["north"],
        "zoneFlows": {
          "north": { "spacing": 8, "crossAxisAlignment": "stretch", "expandSlots": false },
          "center": { "spacing": 8, "mainAxisAlignment": "start", "crossAxisAlignment": "center", "expandSlots": false }
        },
        "placements": {
          "north": ["input-search"],
          "center": ["chip-en-revue", "btn-sort-ttc", "btn-reset-filters"]
        },
        "slotTypes": {
          "input-search": "registry:Value",
          "chip-en-revue": "registry:Action",
          "btn-sort-ttc": "registry:Action",
          "btn-reset-filters": "registry:Action"
        },
        "slotLabels": {
          "input-search": "Champ de recherche instantanée",
          "chip-en-revue": "Filtre dossiers en revue",
          "btn-sort-ttc": "Bouton trier par montant TTC",
          "btn-reset-filters": "Bouton réinitialiser les filtres"
        }
      },
      "input-search": {
        "type": "value",
        "mode": "input",
        "label": "Rechercher",
        "placeholder": "Client ou référence…",
        "field": {
          "prefixIcon": "search"
        }
      },
      "chip-en-revue": {
        "type": "action",
        "kind": "textAndIcon",
        "variant": "surface",
        "icon": "filter_list",
        "label": "En revue",
        "style": {
          "color": "theme:surfaceContainerLow",
          "borderColor": "theme:outlineVariant",
          "borderWidth": 1,
          "radius": 20
        }
      },
      "btn-sort-ttc": {
        "type": "action",
        "kind": "textAndIcon",
        "variant": "outlined",
        "icon": "swap_vert",
        "label": "TTC"
      },
      "btn-reset-filters": {
        "type": "action",
        "kind": "icon",
        "variant": "text",
        "icon": "restart_alt",
        "label": "Réinitialiser"
      },
      "list-dossiers": {
        "type": "list",
        "binding": "pilotage_dossiers:dossiers",
        "allowRemove": true,
        "spacing": 8,
        "template": {
          "zoneAxes": { "center": "column" },
          "zoneFlows": {
            "center": { "spacing": 4, "crossAxisAlignment": "stretch", "expandSlots": false }
          },
          "placements": {
            "center": ["row-client", "row-ttc"]
          },
          "slotTypes": {
            "row-client": "registry:Value",
            "row-ttc": "registry:Value"
          },
          "slotLabels": {
            "row-client": "Nom du client de la ligne",
            "row-ttc": "Montant TTC calculé de la ligne"
          }
        }
      },
      "row-client": {
        "type": "value",
        "binding": "dossiers[?].client",
        "fontSize": 14,
        "fontWeight": "semibold",
        "color": "theme:onSurface"
      },
      "row-ttc": {
        "type": "value",
        "binding": "dossiers[?].@montantTtc",
        "suffix": " € TTC",
        "fontSize": 13,
        "color": "theme:onSurfaceVariant"
      },
      "card-detail": {
        "type": "layout",
        "zoneAxes": { "center": "column", "south": "row" },
        "south": true,
        "autoSides": ["south"],
        "zoneFlows": {
          "center": { "spacing": 14, "crossAxisAlignment": "stretch", "expandSlots": false },
          "south": { "spacing": 12, "mainAxisAlignment": "end", "crossAxisAlignment": "center", "expandSlots": false }
        },
        "placements": {
          "center": ["detail-reference", "detail-client", "detail-montant-ht", "detail-montant-ttc", "detail-statut"],
          "south": ["btn-validate-dossier"]
        },
        "slotTypes": {
          "detail-reference": "registry:Value",
          "detail-client": "registry:Value",
          "detail-montant-ht": "registry:Value",
          "detail-montant-ttc": "registry:Value",
          "detail-statut": "registry:Value",
          "btn-validate-dossier": "registry:Action"
        },
        "slotLabels": {
          "detail-reference": "Champ référence du dossier",
          "detail-client": "Champ client du dossier",
          "detail-montant-ht": "Champ montant HT",
          "detail-montant-ttc": "Affichage montant TTC calculé",
          "detail-statut": "Statut courant du dossier",
          "btn-validate-dossier": "Bouton valider et verrouiller le dossier"
        }
      },
      "detail-reference": {
        "type": "value",
        "mode": "input",
        "label": "Référence",
        "binding": "pilotage_dossiers:dossiers[?].reference"
      },
      "detail-client": {
        "type": "value",
        "mode": "input",
        "label": "Client",
        "binding": "pilotage_dossiers:dossiers[?].client"
      },
      "detail-montant-ht": {
        "type": "value",
        "mode": "input",
        "label": "Montant HT",
        "suffix": " € HT",
        "binding": "pilotage_dossiers:dossiers[?].montantHt"
      },
      "detail-montant-ttc": {
        "type": "value",
        "mode": "display",
        "label": "Total TTC calculé",
        "suffix": " € TTC",
        "binding": "pilotage_dossiers:dossiers[?].@montantTtc",
        "fontWeight": "semibold"
      },
      "detail-statut": {
        "type": "value",
        "mode": "display",
        "label": "Statut",
        "binding": "pilotage_dossiers:dossiers[?].statut"
      },
      "btn-validate-dossier": {
        "type": "action",
        "kind": "textAndIcon",
        "variant": "filled",
        "icon": "verified",
        "label": "Valider le dossier"
      }
    },
    "behaviors": {
      "mainLayout": [
        {
          "id": "b-bind-west-width",
          "event": "onBinding",
          "action": {
            "type": "bindZoneSize",
            "zone": "west",
            "binding": "pilotage_dossiers:ui.westWidth",
            "unit": "pixels",
            "durationMs": 250,
            "curve": "easeInOut"
          }
        }
      ],
      "btn-toggle-sidebar": [
        {
          "id": "b-toggle-west-width",
          "event": "onTap",
          "action": {
            "type": "runJavaScript",
            "repositoryId": "pilotage_dossiers",
            "code": "ctx.set('ui.westWidth', (doc.ui && doc.ui.westWidth > 0) ? 0 : 360);"
          }
        }
      ],
      "btn-add-dossier": [
        {
          "id": "b-create-dossier",
          "event": "onTap",
          "action": {
            "type": "addArrayItem",
            "binding": "pilotage_dossiers:dossiers",
            "selectCreated": true
          }
        }
      ],
      "detail-statut": [
        {
          "id": "b-default-statut-brouillon",
          "event": "onCreate",
          "action": {
            "type": "creationDefault",
            "defaultValue": "brouillon"
          }
        }
      ],
      "detail-client": [
        {
          "id": "b-readonly-when-locked",
          "event": "onBinding",
          "action": {
            "type": "bindState",
            "state": "readOnly",
            "binding": "pilotage_dossiers:dossiers[?].verrouille"
          }
        }
      ],
      "detail-montant-ht": [
        {
          "id": "b-ht-readonly-when-locked",
          "event": "onBinding",
          "action": {
            "type": "bindState",
            "state": "readOnly",
            "binding": "pilotage_dossiers:dossiers[?].verrouille"
          }
        }
      ],
      "list-dossiers": [
        {
          "id": "b-live-search-filter",
          "event": "onBinding",
          "validator": {
            "type": "otherIsFill",
            "targetComponentId": "input-search"
          },
          "action": {
            "type": "filterCollection",
            "predicate": {
              "type": "any",
              "validators": [
                {
                  "type": "bindingContains",
                  "binding": "dossiers[?].client",
                  "expectedComponentId": "input-search",
                  "caseSensitive": false
                },
                {
                  "type": "bindingContains",
                  "binding": "dossiers[?].reference",
                  "expectedComponentId": "input-search",
                  "caseSensitive": false
                }
              ]
            }
          }
        }
      ],
      "list-dossiers:item": [
        {
          "id": "b-row-notes-tooltip",
          "event": "onHover",
          "action": {
            "type": "onTooltip",
            "binding": "dossiers[?].notes"
          }
        }
      ],
      "chip-en-revue": [
        {
          "id": "b-toggle-filter-revue",
          "event": "onTap",
          "action": {
            "type": "filterCollection",
            "mode": "toggle",
            "targetComponentId": "list-dossiers",
            "filterKey": "statut",
            "predicate": {
              "type": "bindingEquals",
              "binding": "dossiers[?].statut",
              "value": "en_revue"
            }
          }
        },
        {
          "id": "b-toggle-chip-style",
          "event": "onTap",
          "action": {
            "type": "setStyle",
            "operation": "toggle",
            "durationMs": 150,
            "style": {
              "backgroundColor": "theme:primaryContainer",
              "foregroundColor": "theme:onPrimaryContainer",
              "borderColor": "theme:primary",
              "borderWidth": 1.5
            }
          }
        }
      ],
      "btn-sort-ttc": [
        {
          "id": "b-sort-by-ttc",
          "event": "onTap",
          "action": {
            "type": "sortCollection",
            "targetComponentId": "list-dossiers",
            "path": "dossiers[?].@montantTtc",
            "direction": "toggle"
          }
        }
      ],
      "btn-reset-filters": [
        {
          "id": "b-clear-all-filters",
          "event": "onTap",
          "action": {
            "type": "filterCollection",
            "mode": "clearAll",
            "targetComponentId": "list-dossiers"
          }
        },
        {
          "id": "b-clear-sort",
          "event": "onTap",
          "action": {
            "type": "sortCollection",
            "mode": "clear",
            "targetComponentId": "list-dossiers"
          }
        },
        {
          "id": "b-reset-chip-style",
          "event": "onTap",
          "action": {
            "type": "setStyle",
            "operation": "reset",
            "targetComponentId": "chip-en-revue"
          }
        }
      ],
      "btn-validate-dossier": [
        {
          "id": "b-disable-when-locked",
          "event": "onBinding",
          "action": {
            "type": "bindState",
            "state": "disabled",
            "binding": "pilotage_dossiers:dossiers[?].verrouille"
          }
        },
        {
          "id": "b-validate-and-lock",
          "event": "onTap",
          "validator": {
            "type": "all",
            "validators": [
              { "type": "otherIsValid", "targetComponentId": "detail-reference" },
              { "type": "otherIsValid", "targetComponentId": "detail-client" },
              { "type": "otherIsValid", "targetComponentId": "detail-montant-ht" },
              {
                "type": "bindingNotEquals",
                "binding": "pilotage_dossiers:dossiers[?].statut",
                "value": "valide"
              }
            ]
          },
          "action": {
            "type": "runJavaScript",
            "repositoryId": "pilotage_dossiers",
            "code": "ctx.set('dossiers[?].statut', 'valide'); ctx.set('dossiers[?].verrouille', true);"
          }
        }
      ]
    },
    "usages": {
      "root": { "kind": "layout" },
      "app-bar": { "kind": "layout" },
      "title-app": { "kind": "explanation", "translationKey": "dossiersPageTitle" },
      "btn-toggle-sidebar": { "kind": "action" },
      "btn-add-dossier": { "kind": "action" },
      "mainLayout": { "kind": "layout" },
      "toolbar-filters": { "kind": "layout" },
      "input-search": { "kind": "userInput" },
      "chip-en-revue": { "kind": "action" },
      "btn-sort-ttc": { "kind": "action" },
      "btn-reset-filters": { "kind": "action" },
      "card-detail": { "kind": "layout" },
      "btn-validate-dossier": { "kind": "action" }
    }
  }
}
```
