/// Moteur partagé de filtrage et de tri côté client ([CollectionViewTransform])
/// pour les composants de collection (`SuperListView` et `SuperTable`).
///
/// Combine de manière homogène :
/// 1. Les règles **déclaratives** (`BehaviorEvent.onBinding`) attachées
///    directement à la collection ([FilterCollectionAction] et [SortCollectionAction]),
///    avec évaluation de leur `validator` comme condition d'activation ou comme
///    prédicat par ligne ;
/// 2. L'état **impératif** enregistré dans [CollectionViewStateRegistry] (actions
///    déclenchées depuis des boutons, en-têtes ou champs de recherche).
///
/// Retourne la liste ordonnée des **indices sources** (`visibleSourceIndices`)
/// afin de préserver intégralement `JsonListScope`, la sélection Maître / Détail,
/// l'édition en place et la suppression sur les éléments du repository.
library;

import 'dart:async' show unawaited;
import 'dart:io' show FileSystemException;

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../models/json_text_binding.dart';
import '../../theme/appearance.dart';
import '../../widgets/components/json_collection_common.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_binding.dart';
import '../repositories/json_repository_store.dart';
import 'behavior_validator_evaluator.dart';
import 'collection_view_state_registry.dart';
import 'component_runtime_value_registry.dart';

/// Dépendances réactives (composants et liaisons) référencées par les règles de
/// tri et de filtrage d'une collection.
@immutable
class CollectionViewDependencies {
  /// Crée un descripteur de dépendances de vue de collection.
  const CollectionViewDependencies({
    this.componentIds = const {},
    this.bindings = const [],
  });

  /// Ensemble vide (aucune dépendance externe).
  static const empty = CollectionViewDependencies();

  /// Identifiants techniques de composants à observer sur [ComponentRuntimeValueRegistry].
  final Set<String> componentIds;

  /// Liaisons repository référencées par les validateurs/prédicats.
  final List<JsonTextBinding> bindings;
}

/// Service stateless calculant les indices visibles triés et filtrés d'une collection.
abstract final class CollectionViewTransform {
  static final RegExp _isoDatePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// Indique si au moins une règle déclarative (`onBinding`) ou impérative de tri
  /// ou de filtrage est active pour la collection.
  static bool hasActiveRules(
    List<ComponentBehavior> behaviors,
    CollectionRuntimeViewState runtimeState,
  ) {
    if (!runtimeState.isEmpty) return true;
    for (final behavior in behaviors) {
      if (!behavior.enabled || behavior.event != BehaviorEvent.onBinding) {
        continue;
      }
      if (behavior.action is SortCollectionAction ||
          behavior.action is FilterCollectionAction) {
        return true;
      }
    }
    return false;
  }

  /// Collecte les identifiants de composants et liaisons référencés par les règles
  /// déclaratives et les filtres impératifs actifs.
  static CollectionViewDependencies collectDependencies(
    List<ComponentBehavior> behaviors,
    CollectionRuntimeViewState runtimeState,
  ) {
    final componentIds = <String>{};
    final bindings = <JsonTextBinding>[];

    void addValidator(BehaviorValidator? validator) {
      if (validator == null) return;
      componentIds.addAll(validator.referencedComponentIds);
      bindings.addAll(validator.referencedBindings);
    }

    for (final behavior in behaviors) {
      if (!behavior.enabled || behavior.event != BehaviorEvent.onBinding) {
        continue;
      }
      if (behavior.action case final FilterCollectionAction filter) {
        addValidator(behavior.validator);
        addValidator(filter.predicate);
      } else if (behavior.action is SortCollectionAction) {
        addValidator(behavior.validator);
      }
    }
    for (final predicate in runtimeState.filters.values) {
      addValidator(predicate);
    }

    return CollectionViewDependencies(
      componentIds: componentIds.isEmpty
          ? const {}
          : Set<String>.unmodifiable(componentIds),
      bindings: bindings.isEmpty
          ? const []
          : List<JsonTextBinding>.unmodifiable(bindings),
    );
  }

  /// Tente un calcul purement synchrone des indices visibles filtrés et triés.
  ///
  /// Retourne `null` si une lecture asynchrone (repository non en cache ou
  /// attribut calculé `@`) est nécessaire : l'appelant bascule alors sur [resolve].
  static List<int>? tryResolveSync({
    required BuildContext context,
    required String componentId,
    required String componentType,
    required List<Object?> items,
    required ResolvedJsonArraySource? source,
    required String? arrayTemplate,
    required List<ComponentBehavior> behaviors,
    required CollectionRuntimeViewState runtimeState,
    required Appearance? appearance,
    required JsonRepositoryStore? store,
    required JsonListScope? parentScope,
    required bool editing,
    ComponentRuntimeValueRegistry? valueRegistry,
  }) {
    if (editing || items.isEmpty || !hasActiveRules(behaviors, runtimeState)) {
      return List<int>.generate(items.length, (i) => i, growable: false);
    }

    final parentCtx = BehaviorValidationContext(
      context: context,
      componentId: componentId,
      componentType: componentType,
      event: BehaviorEvent.onBinding,
      executionData: {'value': items},
      appearance: appearance,
      repositoryStore: store,
      listScope: parentScope,
      valueRegistry: valueRegistry,
    );

    final activeFilters = <BehaviorValidator>[];
    final declarativeSort = <CollectionSortCriterion>[];

    for (final behavior in behaviors) {
      if (!behavior.enabled || behavior.event != BehaviorEvent.onBinding) {
        continue;
      }
      if (behavior.action case final FilterCollectionAction filter) {
        if (filter.predicate != null) {
          if (behavior.validator != null) {
            final guard = BehaviorValidatorEvaluator.tryEvaluateSync(
              behavior.validator!,
              parentCtx,
            );
            if (guard == null) return null;
            if (!guard) continue;
          }
          activeFilters.add(filter.predicate!);
        } else if (behavior.validator != null) {
          activeFilters.add(behavior.validator!);
        }
      } else if (behavior.action case final SortCollectionAction sort) {
        if (sort.mode == CollectionSortMode.clear) continue;
        if (behavior.validator != null) {
          final guard = BehaviorValidatorEvaluator.tryEvaluateSync(
            behavior.validator!,
            parentCtx,
          );
          if (guard == null) return null;
          if (!guard) continue;
        }
        declarativeSort.addAll(sort.criteria);
      }
    }

    activeFilters.addAll(runtimeState.filters.values);

    final effectiveSort =
        runtimeState.sortCriteria != null &&
            runtimeState.sortCriteria!.isNotEmpty
        ? runtimeState.sortCriteria!
        : declarativeSort;

    final indices = <int>[];
    if (activeFilters.isEmpty) {
      for (var i = 0; i < items.length; i++) {
        indices.add(i);
      }
    } else {
      for (var i = 0; i < items.length; i++) {
        final rowScope = _rowScopeFor(
          source: source,
          parentScope: parentScope,
          arrayTemplate: arrayTemplate,
          sourceIndex: i,
        );
        final rowCtx = BehaviorValidationContext(
          context: context,
          componentId: componentId,
          componentType: componentType,
          event: BehaviorEvent.onBinding,
          executionData: {'value': items[i], 'index': i},
          appearance: appearance,
          repositoryStore: store,
          listScope: rowScope,
          rowItem: items[i],
          valueRegistry: valueRegistry,
        );
        var matches = true;
        for (final predicate in activeFilters) {
          final result = BehaviorValidatorEvaluator.tryEvaluateSync(
            predicate,
            rowCtx,
          );
          if (result == null) return null;
          if (!result) {
            matches = false;
            break;
          }
        }
        if (matches) indices.add(i);
      }
    }

    if (effectiveSort.isEmpty || indices.length <= 1) {
      return List<int>.unmodifiable(indices);
    }

    final keysByIndex = <int, List<Object?>>{};
    for (final sourceIndex in indices) {
      final rowScope = _rowScopeFor(
        source: source,
        parentScope: parentScope,
        arrayTemplate: arrayTemplate,
        sourceIndex: sourceIndex,
      );
      final keys = <Object?>[];
      for (final criterion in effectiveSort) {
        final keyResult = _tryReadSortKeySync(
          criterion: criterion,
          rowItem: items[sourceIndex],
          rowScope: rowScope,
          arrayTemplate: arrayTemplate,
          store: store,
        );
        if (keyResult == null) return null;
        keys.add(keyResult.value);
      }
      keysByIndex[sourceIndex] = keys;
    }

    _stableSortIndices(indices, keysByIndex, effectiveSort);
    return List<int>.unmodifiable(indices);
  }

  /// Calcule de manière asynchrone les indices visibles filtrés et triés.
  static Future<List<int>> resolve({
    required BuildContext context,
    required String componentId,
    required String componentType,
    required List<Object?> items,
    required ResolvedJsonArraySource? source,
    required String? arrayTemplate,
    required List<ComponentBehavior> behaviors,
    required CollectionRuntimeViewState runtimeState,
    required Appearance? appearance,
    required JsonRepositoryStore? store,
    required JsonListScope? parentScope,
    required bool editing,
    ComponentRuntimeValueRegistry? valueRegistry,
  }) async {
    if (editing || items.isEmpty || !hasActiveRules(behaviors, runtimeState)) {
      return List<int>.generate(items.length, (i) => i, growable: false);
    }

    final parentCtx = BehaviorValidationContext(
      context: context,
      componentId: componentId,
      componentType: componentType,
      event: BehaviorEvent.onBinding,
      executionData: {'value': items},
      appearance: appearance,
      repositoryStore: store,
      listScope: parentScope,
      valueRegistry: valueRegistry,
    );

    final activeFilters = <BehaviorValidator>[];
    final declarativeSort = <CollectionSortCriterion>[];

    for (final behavior in behaviors) {
      if (!behavior.enabled || behavior.event != BehaviorEvent.onBinding) {
        continue;
      }
      if (behavior.action case final FilterCollectionAction filter) {
        if (filter.predicate != null) {
          if (behavior.validator != null) {
            final guard = await BehaviorValidatorEvaluator.evaluate(
              behavior.validator!,
              parentCtx,
            );
            if (!guard) continue;
          }
          activeFilters.add(filter.predicate!);
        } else if (behavior.validator != null) {
          activeFilters.add(behavior.validator!);
        }
      } else if (behavior.action case final SortCollectionAction sort) {
        if (sort.mode == CollectionSortMode.clear) continue;
        if (behavior.validator != null) {
          final guard = await BehaviorValidatorEvaluator.evaluate(
            behavior.validator!,
            parentCtx,
          );
          if (!guard) continue;
        }
        declarativeSort.addAll(sort.criteria);
      }
    }

    activeFilters.addAll(runtimeState.filters.values);

    final effectiveSort =
        runtimeState.sortCriteria != null &&
            runtimeState.sortCriteria!.isNotEmpty
        ? runtimeState.sortCriteria!
        : declarativeSort;

    final indices = <int>[];
    if (activeFilters.isEmpty) {
      for (var i = 0; i < items.length; i++) {
        indices.add(i);
      }
    } else {
      for (var i = 0; i < items.length; i++) {
        if (!context.mounted) return const [];
        final rowScope = _rowScopeFor(
          source: source,
          parentScope: parentScope,
          arrayTemplate: arrayTemplate,
          sourceIndex: i,
        );
        final rowCtx = BehaviorValidationContext(
          context: context,
          componentId: componentId,
          componentType: componentType,
          event: BehaviorEvent.onBinding,
          executionData: {'value': items[i], 'index': i},
          appearance: appearance,
          repositoryStore: store,
          listScope: rowScope,
          rowItem: items[i],
          valueRegistry: valueRegistry,
        );
        var matches = true;
        for (final predicate in activeFilters) {
          if (!await BehaviorValidatorEvaluator.evaluate(predicate, rowCtx)) {
            matches = false;
            break;
          }
        }
        if (matches) indices.add(i);
      }
    }

    if (effectiveSort.isEmpty || indices.length <= 1) {
      return List<int>.unmodifiable(indices);
    }

    final keysByIndex = <int, List<Object?>>{};
    for (final sourceIndex in indices) {
      final rowScope = _rowScopeFor(
        source: source,
        parentScope: parentScope,
        arrayTemplate: arrayTemplate,
        sourceIndex: sourceIndex,
      );
      final keys = <Object?>[];
      for (final criterion in effectiveSort) {
        final key = await _readSortKeyAsync(
          criterion: criterion,
          rowItem: items[sourceIndex],
          rowScope: rowScope,
          arrayTemplate: arrayTemplate,
          store: store,
        );
        keys.add(key);
      }
      keysByIndex[sourceIndex] = keys;
    }

    _stableSortIndices(indices, keysByIndex, effectiveSort);
    return List<int>.unmodifiable(indices);
  }

  /// Compare deux valeurs selon [criterion] (typé, gestion de la casse et des nulls).
  static int compareValues(
    Object? a,
    Object? b,
    CollectionSortCriterion criterion,
  ) {
    if (a == null && b == null) return 0;
    if (a == null) return criterion.nullsLast ? 1 : -1;
    if (b == null) return criterion.nullsLast ? -1 : 1;

    final int raw;
    if (a is num && b is num) {
      raw = a.compareTo(b);
    } else if (a is bool && b is bool) {
      raw = (a ? 1 : 0).compareTo(b ? 1 : 0);
    } else if (a is String && b is String) {
      final dateCmp = _tryCompareIsoDates(a, b);
      if (dateCmp != null) {
        raw = dateCmp;
      } else {
        raw = criterion.caseSensitive
            ? a.compareTo(b)
            : a.toLowerCase().compareTo(b.toLowerCase());
      }
    } else if (a is num && b is String) {
      final parsed = num.tryParse(b.trim().replaceAll(',', '.'));
      raw = parsed != null ? a.compareTo(parsed) : a.toString().compareTo(b);
    } else if (a is String && b is num) {
      final parsed = num.tryParse(a.trim().replaceAll(',', '.'));
      raw = parsed != null ? parsed.compareTo(b) : a.compareTo(b.toString());
    } else {
      final sa = a.toString();
      final sb = b.toString();
      raw = criterion.caseSensitive
          ? sa.compareTo(sb)
          : sa.toLowerCase().compareTo(sb.toLowerCase());
    }

    return criterion.direction == CollectionSortDirection.desc ? -raw : raw;
  }

  static int? _tryCompareIsoDates(String a, String b) {
    if (a.length < 10 || b.length < 10) return null;
    if (!_isoDatePrefix.hasMatch(a) || !_isoDatePrefix.hasMatch(b)) return null;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return null;
    return da.compareTo(db);
  }

  static void _stableSortIndices(
    List<int> indices,
    Map<int, List<Object?>> keysByIndex,
    List<CollectionSortCriterion> criteria,
  ) {
    indices.sort((a, b) {
      final keysA = keysByIndex[a]!;
      final keysB = keysByIndex[b]!;
      for (var c = 0; c < criteria.length; c++) {
        final cmp = compareValues(keysA[c], keysB[c], criteria[c]);
        if (cmp != 0) return cmp;
      }
      return a.compareTo(b);
    });
  }

  static JsonListScope _rowScopeFor({
    required ResolvedJsonArraySource? source,
    required JsonListScope? parentScope,
    required String? arrayTemplate,
    required int sourceIndex,
  }) {
    final basePath = source?.binding?.path;
    return JsonListScope(
      repositoryId: source?.binding?.repositoryId ?? parentScope?.repositoryId,
      indices: [...?(source?.rowBase ?? parentScope?.indices), sourceIndex],
      arrayTemplate: arrayTemplate,
      nodePath: basePath == null ? null : '$basePath[$sourceIndex]',
      treeTemplatePath: arrayTemplate,
      child: const SizedBox.shrink(),
    );
  }

  static ({Object? value})? _tryReadLocalSortKey({
    required String rawPath,
    required Object? rowItem,
    required String? arrayTemplate,
  }) {
    final trimmed = rawPath.trim();
    if (trimmed == '.') return (value: rowItem);
    if (JsonTextBinding.isCalculatedPath(trimmed)) return null;

    String? relativePath;
    if (arrayTemplate != null && arrayTemplate.isNotEmpty) {
      final wildcardPrefix = '$arrayTemplate[?]';
      if (trimmed == wildcardPrefix) return (value: rowItem);
      if (trimmed.startsWith('$wildcardPrefix.')) {
        relativePath = trimmed.substring(wildcardPrefix.length + 1);
      }
    }
    if (relativePath == null && !trimmed.contains('[?]')) {
      relativePath = trimmed;
    }
    if (relativePath == null || relativePath.isEmpty) return null;
    if (rowItem == null) return (value: null);
    try {
      return (value: JsonAttributePath(relativePath).readNode(rowItem));
    } on FormatException {
      return (value: null);
    }
  }

  static ({Object? value})? _tryReadSortKeySync({
    required CollectionSortCriterion criterion,
    required Object? rowItem,
    required JsonListScope rowScope,
    required String? arrayTemplate,
    required JsonRepositoryStore? store,
  }) {
    final local = _tryReadLocalSortKey(
      rawPath: criterion.path,
      rowItem: rowItem,
      arrayTemplate: arrayTemplate,
    );
    if (local != null) return local;
    if (store == null) return (value: null);
    try {
      final selected = JsonListScope.resolveSelected(
        JsonTextBinding(path: criterion.path.trim()),
        rowScope,
        store,
      );
      final resolved = selected.binding;
      if (resolved == null) return (value: null);
      final cached = store.peekAttribute(resolved);
      if (cached != null) return (value: cached.value);
      return null;
    } on FormatException {
      return (value: null);
    }
  }

  static Future<Object?> _readSortKeyAsync({
    required CollectionSortCriterion criterion,
    required Object? rowItem,
    required JsonListScope rowScope,
    required String? arrayTemplate,
    required JsonRepositoryStore? store,
  }) async {
    final local = _tryReadLocalSortKey(
      rawPath: criterion.path,
      rowItem: rowItem,
      arrayTemplate: arrayTemplate,
    );
    if (local != null) return local.value;
    if (store == null) return null;
    try {
      final selected = JsonListScope.resolveSelected(
        JsonTextBinding(path: criterion.path.trim()),
        rowScope,
        store,
      );
      final resolved = selected.binding;
      if (resolved == null) return null;
      final cached = store.peekAttribute(resolved);
      if (cached != null) return cached.value;
      final attr = await store.readAttribute(resolved);
      return attr.value;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }
}

/// Contrôleur réactif mutualisé entre `SuperListView` et `SuperTable` pour
/// observer les règles de tri/filtre (déclaratives et impératives) et maintenir
/// la table de correspondance `visualIndex -> sourceIndex`.
class CollectionViewTransformController {
  /// Crée un contrôleur lié à [onChanged] (typiquement `() { if (mounted) setState(() {}); }`).
  CollectionViewTransformController({
    required this.onChanged,
    CollectionViewStateRegistry? stateRegistry,
    ComponentRuntimeValueRegistry? valueRegistry,
  }) : _stateRegistry = stateRegistry ?? CollectionViewStateRegistry.instance,
       _valueRegistry = valueRegistry ?? ComponentRuntimeValueRegistry.instance;

  /// Callback appelé lorsqu'un état externe (tri/filtre impératif, composant
  /// référencé, sélection externe ou résolution asynchrone) demande une reconstruction.
  final VoidCallback onChanged;

  final CollectionViewStateRegistry _stateRegistry;
  final ComponentRuntimeValueRegistry _valueRegistry;

  String? _observedComponentId;
  Set<String> _watchedComponentIds = const {};
  List<JsonArrayBinding> _watchedSelections = const [];
  List<int>? _asyncResolvedIndices;
  int _generation = 0;
  bool _disposed = false;

  void _handleExternalChange() {
    if (_disposed) return;
    _asyncResolvedIndices = null;
    onChanged();
  }

  void _syncSubscriptions({
    required String componentId,
    required List<ComponentBehavior> behaviors,
    required CollectionRuntimeViewState runtimeState,
    required JsonListScope? parentScope,
    required JsonRepositoryStore? store,
  }) {
    if (_observedComponentId != componentId) {
      if (_observedComponentId != null) {
        _stateRegistry.removeListenerFor(
          _observedComponentId!,
          _handleExternalChange,
        );
      }
      _observedComponentId = componentId;
      _stateRegistry.addListenerFor(componentId, _handleExternalChange);
    }

    final deps = CollectionViewTransform.collectDependencies(
      behaviors,
      runtimeState,
    );

    if (!setEquals(_watchedComponentIds, deps.componentIds)) {
      for (final oldId in _watchedComponentIds) {
        if (!deps.componentIds.contains(oldId)) {
          _valueRegistry.removeComponentListener(oldId, _handleExternalChange);
        }
      }
      for (final newId in deps.componentIds) {
        if (!_watchedComponentIds.contains(newId)) {
          _valueRegistry.addComponentListener(newId, _handleExternalChange);
        }
      }
      _watchedComponentIds = deps.componentIds;
    }

    final nextSelections = <JsonArrayBinding>{};
    if (store != null && deps.bindings.isNotEmpty) {
      for (final binding in deps.bindings) {
        try {
          final resolved = JsonListScope.resolveSelected(
            binding,
            parentScope,
            store,
          );
          nextSelections.addAll(resolved.arrays);
        } on FormatException {
          // Une liaison de ligne avec [?] non résolu au niveau parent sera résolue par ligne.
        }
      }
    }
    final nextList = nextSelections.toList();
    if (!listEquals(_watchedSelections, nextList)) {
      _watchedSelections = updateWatchedArrayBindings(
        _watchedSelections,
        nextList,
        _handleExternalChange,
      );
    }
  }

  /// Met à jour les abonnements et retourne la liste ordonnée des indices sources
  /// visibles pour [items].
  List<int> resolveVisibleIndices({
    required BuildContext context,
    required String componentId,
    required String componentType,
    required List<Object?>? items,
    required ResolvedJsonArraySource? source,
    required String? arrayTemplate,
    required List<ComponentBehavior> behaviors,
    required Appearance? appearance,
    required JsonRepositoryStore? store,
    required JsonListScope? parentScope,
    required bool editing,
  }) {
    final runtimeState = _stateRegistry.stateFor(componentId);
    _syncSubscriptions(
      componentId: componentId,
      behaviors: behaviors,
      runtimeState: runtimeState,
      parentScope: parentScope,
      store: store,
    );

    if (items == null || items.isEmpty) {
      _asyncResolvedIndices = null;
      return const [];
    }

    if (editing ||
        !CollectionViewTransform.hasActiveRules(behaviors, runtimeState)) {
      _asyncResolvedIndices = null;
      return List<int>.generate(items.length, (i) => i, growable: false);
    }

    final syncResult = CollectionViewTransform.tryResolveSync(
      context: context,
      componentId: componentId,
      componentType: componentType,
      items: items,
      source: source,
      arrayTemplate: arrayTemplate,
      behaviors: behaviors,
      runtimeState: runtimeState,
      appearance: appearance,
      store: store,
      parentScope: parentScope,
      editing: editing,
      valueRegistry: _valueRegistry,
    );
    if (syncResult != null) {
      _asyncResolvedIndices = syncResult;
      return syncResult;
    }

    final generation = ++_generation;
    unawaited(() async {
      final resolved = await CollectionViewTransform.resolve(
        context: context,
        componentId: componentId,
        componentType: componentType,
        items: items,
        source: source,
        arrayTemplate: arrayTemplate,
        behaviors: behaviors,
        runtimeState: runtimeState,
        appearance: appearance,
        store: store,
        parentScope: parentScope,
        editing: editing,
        valueRegistry: _valueRegistry,
      );
      if (_disposed || generation != _generation) return;
      if (!listEquals(_asyncResolvedIndices, resolved)) {
        _asyncResolvedIndices = resolved;
        onChanged();
      }
    }());

    final fallback = _asyncResolvedIndices;
    if (fallback != null &&
        fallback.every((idx) => idx >= 0 && idx < items.length)) {
      return fallback;
    }
    return List<int>.generate(items.length, (i) => i, growable: false);
  }

  /// Libère tous les abonnements enregistrés.
  void dispose() {
    _disposed = true;
    _generation++;
    if (_observedComponentId != null) {
      _stateRegistry.removeListenerFor(
        _observedComponentId!,
        _handleExternalChange,
      );
      _observedComponentId = null;
    }
    for (final id in _watchedComponentIds) {
      _valueRegistry.removeComponentListener(id, _handleExternalChange);
    }
    _watchedComponentIds = const {};
    _watchedSelections = updateWatchedArrayBindings(
      _watchedSelections,
      const [],
      _handleExternalChange,
    );
    _asyncResolvedIndices = null;
  }
}

