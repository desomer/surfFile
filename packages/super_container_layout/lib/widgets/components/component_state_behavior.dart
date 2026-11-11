/// Application réactive des comportements d'état ([StateBindingAction]) par identifiant de composant.
///
/// Observe les booléens liés dans les repositories JSON sans jamais écrire dans
/// les repositories ni modifier l'[Appearance], et expose les états résolus
/// (`invisible`, `readOnly`, `disabled`) via [ComponentBehaviorStateScope].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/component_behavior.dart';
import '../../models/json_text_binding.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../theme/appearance.dart';
import '../editing/slots/editor_selection_region.dart';
import '../editing/slots/editor_slot.dart' show StyleEditScope;

/// Portée héritée exposant les états forcés par les [StateBindingAction] actives.
class ComponentBehaviorStateScope extends InheritedWidget {
  const ComponentBehaviorStateScope({
    required this.invisible,
    required this.maintainSize,
    required this.readOnly,
    required this.disabled,
    required super.child,
    super.key,
  });

  /// Indique si le composant (ou un ancêtre) est rendu invisible par un comportement.
  final bool invisible;

  /// Indique si l'espace est conservé lorsque [invisible] est actif.
  final bool maintainSize;

  /// Indique si le composant (ou un ancêtre) est forcé en lecture seule.
  final bool readOnly;

  /// Indique si le composant (ou un ancêtre) est forcé en état inactif (`disabled`).
  final bool disabled;

  /// Retourne la portée d'état de comportement la plus proche, ou `null`.
  static ComponentBehaviorStateScope? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ComponentBehaviorStateScope>();

  /// Indique si le contexte courant est marqué inactif par un comportement.
  static bool isDisabled(BuildContext context) =>
      maybeOf(context)?.disabled ?? false;

  /// Indique si le contexte courant est marqué en lecture seule par un comportement.
  static bool isReadOnly(BuildContext context) =>
      maybeOf(context)?.readOnly ?? false;

  /// Indique si le contexte courant est marqué invisible par un comportement.
  static bool isInvisible(BuildContext context) =>
      maybeOf(context)?.invisible ?? false;

  /// États automatiques ([AutomaticState.disabled], [AutomaticState.readOnly])
  /// activés par les comportements englobants.
  static Set<AutomaticState> automaticStatesOf(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) return const {};
    return {
      if (scope.disabled) AutomaticState.disabled,
      if (scope.readOnly) AutomaticState.readOnly,
    };
  }

  @override
  bool updateShouldNotify(ComponentBehaviorStateScope oldWidget) =>
      invisible != oldWidget.invisible ||
      maintainSize != oldWidget.maintainSize ||
      readOnly != oldWidget.readOnly ||
      disabled != oldWidget.disabled;
}

/// Enveloppe réactive évaluant les [StateBindingAction] associées à [componentId].
///
/// Supporte les contextes box et sliver ainsi que la déduplication des slots
/// imbriqués partageant le même [componentId].
class ComponentStateBehavior extends StatefulWidget {
  const ComponentStateBehavior({
    required this.componentId,
    required this.child,
    this.behaviors,
    this.sliver,
    super.key,
  });

  final String componentId;
  final Widget child;

  /// Une liste explicite remplace les comportements de l'apparence.
  final List<ComponentBehavior>? behaviors;

  /// À défaut, utilise le contexte de rendu du slot ([SliverSlotScope]).
  final bool? sliver;

  /// Actions [StateBindingAction] activées pour [componentId], hors mode édition.
  static List<StateBindingAction> actionsOf(
    BuildContext context,
    String componentId, {
    List<ComponentBehavior>? behaviors,
  }) {
    if (StyleEditScope.controllerOf(context)?.value ?? false) {
      return const [];
    }
    final items =
        behaviors ?? AppearanceScope.of(context).behaviorsFor(componentId);
    return [
      for (final behavior in items)
        if (behavior.enabled &&
            behavior.trigger == BehaviorTrigger.binding &&
            behavior.action is StateBindingAction)
          behavior.action as StateBindingAction,
    ];
  }

  @override
  State<ComponentStateBehavior> createState() => _ComponentStateBehaviorState();
}

class _StateBehaviorOwnerScope extends InheritedWidget {
  const _StateBehaviorOwnerScope({
    required this.owners,
    required super.child,
  });

  final Map<String, _ComponentStateBehaviorState> owners;

  @override
  bool updateShouldNotify(_StateBehaviorOwnerScope oldWidget) =>
      owners != oldWidget.owners;
}

typedef _StateBehaviorOverride = ({
  List<ComponentBehavior> behaviors,
  JsonRepositoryStore? store,
  JsonListScope? scope,
});

class _ComponentStateBehaviorState extends State<ComponentStateBehavior> {
  final _childKey = GlobalKey();
  final _overrides = <Object, _StateBehaviorOverride>{};
  _ComponentStateBehaviorState? _overrideOwner;

  List<StateBindingAction> _actions = const [];
  JsonRepositoryStore? _store;
  String? _scopeRepositoryId;
  String? _scopeNodePath;
  List<int> _scopeIndices = const [];
  bool _scopePlaceholder = false;
  List<JsonArrayBinding> _selections = const [];
  Map<int, JsonTextBinding> _resolved = const {};
  Set<BehaviorBoundState> _activeStates = const {};
  bool _maintainSize = false;
  String? _lastError;
  int _generation = 0;
  bool _dirty = true;
  bool _scheduled = false;

  void _detachOverride() {
    final owner = _overrideOwner;
    _overrideOwner = null;
    if (owner?._overrides.remove(this) != null) {
      owner!._markDirtyAndRebuild();
    }
  }

  void _override(
    _ComponentStateBehaviorState owner,
    _StateBehaviorOverride value,
  ) {
    if (!identical(_overrideOwner, owner)) _detachOverride();
    _overrideOwner = owner;
    final previous = owner._overrides[this];
    if (previous != null &&
        listEquals(previous.behaviors, value.behaviors) &&
        identical(previous.store, value.store) &&
        identical(previous.scope, value.scope)) {
      return;
    }
    owner._overrides[this] = value;
    owner._markDirtyAndRebuild();
  }

  void _markDirtyAndRebuild() {
    _dirty = true;
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _listenSelections(List<JsonArrayBinding> selections) {
    if (listEquals(_selections, selections)) return;
    for (final selection in _selections) {
      selection.removeListener(_selectionChanged);
    }
    _selections = selections;
    for (final selection in selections) {
      selection.addListener(_selectionChanged);
    }
  }

  void _selectionChanged() {
    _dirty = true;
    if (mounted) setState(() {});
  }

  void _storeChanged() => _loadAsync();

  void _clearBindings() {
    _generation++;
    _listenSelections(const []);
    _store?.removeListener(_storeChanged);
    _store?.unregisterBindings(this);
    _store = null;
    _actions = const [];
    _resolved = const {};
    _activeStates = const {};
    _maintainSize = false;
    _lastError = null;
    _dirty = true;
  }

  void _sync(
    List<StateBindingAction> actions,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final placeholder = scope?.placeholder ?? false;
    final sameContext =
        !_dirty &&
        listEquals(actions, _actions) &&
        identical(store, _store) &&
        _scopeRepositoryId == scope?.repositoryId &&
        _scopeNodePath == scope?.nodePath &&
        listEquals(_scopeIndices, scope?.indices ?? const []) &&
        _scopePlaceholder == placeholder;
    if (sameContext) return;

    _dirty = false;
    _actions = actions;
    _scopeRepositoryId = scope?.repositoryId;
    _scopeNodePath = scope?.nodePath;
    _scopeIndices = List.of(scope?.indices ?? const []);
    _scopePlaceholder = placeholder;

    if (!identical(store, _store)) {
      _store?.removeListener(_storeChanged);
      _store?.unregisterBindings(this);
      store?.addListener(_storeChanged);
      _store = store;
    }

    if (actions.isEmpty || placeholder) {
      store?.unregisterBindings(this);
      _listenSelections(const []);
      _resolved = const {};
      _activeStates = const {};
      _maintainSize = false;
      _lastError = null;
      return;
    }

    store?.registerBindings(this, [
      for (final action in actions)
        action.binding.repositoryId ?? scope?.repositoryId,
    ]);

    final selections = <JsonArrayBinding>{};
    final resolved = <int, JsonTextBinding>{};
    for (final (index, action) in actions.indexed) {
      try {
        final result = JsonListScope.resolveSelected(
          action.binding,
          scope,
          store,
        );
        selections.addAll(result.arrays);
        if (result.binding != null) {
          resolved[index] = result.binding!;
        }
      } on FormatException catch (error) {
        _reportError(store, error.message);
      }
    }
    _listenSelections(selections.toList());
    _resolved = resolved;

    if (store == null) {
      _activeStates = const {};
      _maintainSize = false;
      return;
    }

    final nextStates = <BehaviorBoundState>{};
    var nextMaintainSize = false;
    var needsAsyncRead = false;
    for (final entry in resolved.entries) {
      final action = actions[entry.key];
      final cached = store.peekAttribute(entry.value);
      if (cached == null) {
        needsAsyncRead = true;
        continue;
      }
      try {
        if (action.matchesValue(cached.value)) {
          nextStates.add(action.state);
          if (action.state == BehaviorBoundState.invisible &&
              action.maintainSize) {
            nextMaintainSize = true;
          }
        }
      } on FormatException catch (error) {
        _reportError(store, error.message);
      }
    }
    _activeStates = nextStates;
    _maintainSize = nextMaintainSize;
    if (needsAsyncRead) {
      _loadAsync();
    }
  }

  void _loadAsync() {
    final store = _store;
    final actions = _actions;
    final resolved = Map.of(_resolved);
    if (store == null || actions.isEmpty || resolved.isEmpty) return;
    final generation = ++_generation;
    unawaited(() async {
      final nextStates = <BehaviorBoundState>{};
      var nextMaintainSize = false;
      for (final entry in resolved.entries) {
        if (!mounted || generation != _generation) return;
        final action = actions[entry.key];
        try {
          final attr = await store.readAttribute(entry.value);
          if (!mounted || generation != _generation) return;
          if (action.matchesValue(attr.value)) {
            nextStates.add(action.state);
            if (action.state == BehaviorBoundState.invisible &&
                action.maintainSize) {
              nextMaintainSize = true;
            }
          }
        } on FormatException catch (error) {
          if (!mounted || generation != _generation) return;
          _reportError(store, error.message);
        } on FileSystemException {
          if (!mounted || generation != _generation) return;
          _reportError(store, 'Impossible de lire le repository lié.');
        }
      }
      if (!mounted || generation != _generation) return;
      if (!setEquals(_activeStates, nextStates) ||
          _maintainSize != nextMaintainSize) {
        setState(() {
          _activeStates = nextStates;
          _maintainSize = nextMaintainSize;
        });
      }
    }());
  }

  void _reportError(JsonRepositoryStore? store, String message) {
    final formatted = 'État lié ${widget.componentId} : $message';
    if (formatted == _lastError) return;
    _lastError = formatted;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(store, _store)) {
        store?.reportBindingError(formatted);
      }
    });
  }

  @override
  void dispose() {
    _detachOverride();
    _clearBindings();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentOwnerScope = context
        .dependOnInheritedWidgetOfExactType<_StateBehaviorOwnerScope>();
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    final owner = parentOwnerScope?.owners[widget.componentId];
    if (owner != null) {
      if (widget.behaviors case final behaviors?) {
        _override(owner, (
          behaviors: behaviors,
          store: JsonRepositoryScope.maybeOf(context),
          scope: JsonListScope.maybeOf(context),
        ));
      } else {
        _detachOverride();
      }
      _clearBindings();
      return child;
    }
    _detachOverride();

    final override = _overrides.values.lastOrNull;
    final actions = ComponentStateBehavior.actionsOf(
      context,
      widget.componentId,
      behaviors: override?.behaviors ?? widget.behaviors,
    );
    final store = override == null
        ? JsonRepositoryScope.maybeOf(context)
        : override.store;
    final scope = override == null
        ? JsonListScope.maybeOf(context)
        : override.scope;
    _sync(actions, scope, store);

    final parentStateScope = ComponentBehaviorStateScope.maybeOf(context);
    final localInvisible = _activeStates.contains(BehaviorBoundState.invisible);
    final localDisabled = _activeStates.contains(BehaviorBoundState.disabled);
    final localReadOnly = _activeStates.contains(BehaviorBoundState.readOnly);

    final effectiveInvisible =
        (parentStateScope?.invisible ?? false) || localInvisible;
    final effectiveMaintainSize = localInvisible
        ? _maintainSize
        : (parentStateScope?.maintainSize ?? false);
    final effectiveDisabled =
        (parentStateScope?.disabled ?? false) || localDisabled;
    final effectiveReadOnly =
        (parentStateScope?.readOnly ?? false) || localReadOnly;

    final isSliver = widget.sliver ?? SliverSlotScope.isSliver(context);
    Widget content = child;

    if (localDisabled) {
      content = isSliver
          ? SliverIgnorePointer(ignoring: true, sliver: content)
          : IgnorePointer(
              ignoring: true,
              child: ExcludeFocus(excluding: true, child: content),
            );
    }

    if (localInvisible) {
      content = isSliver
          ? SliverVisibility(
              visible: false,
              maintainSize: _maintainSize,
              maintainAnimation: _maintainSize,
              maintainState: _maintainSize,
              sliver: content,
            )
          : Visibility(
              visible: false,
              maintainSize: _maintainSize,
              maintainAnimation: _maintainSize,
              maintainState: _maintainSize,
              child: content,
            );
    }

    return _StateBehaviorOwnerScope(
      owners: {...?parentOwnerScope?.owners, widget.componentId: this},
      child: ComponentBehaviorStateScope(
        invisible: effectiveInvisible,
        maintainSize: effectiveMaintainSize,
        readOnly: effectiveReadOnly,
        disabled: effectiveDisabled,
        child: content,
      ),
    );
  }
}
