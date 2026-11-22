/// Application réactive des comportements d'état ([StateBindingAction]) par identifiant de composant.
///
/// Observe les booléens liés dans les repositories JSON sans jamais écrire dans
/// les repositories ni modifier l'[Appearance], et expose les états résolus
/// (`invisible`, `readOnly`, `disabled`) via [ComponentBehaviorStateScope].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/component_behavior.dart';
import '../../models/json_text_binding.dart';
import '../../services/behaviors/behavior_runtime_state_controller.dart';
import '../../services/behaviors/component_runtime_value_registry.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../theme/appearance.dart';
import '../../theme/container_style.dart';
import '../../theme/theme_color.dart';
import '../editing/slots/editor_selection_region.dart';
import '../editing/slots/editor_slot.dart' show StyleEditScope;
import '../appearance/appearance_scope.dart';
import '../surfaces/styled_surface.dart';

/// Niveau de prise en charge native d'un [BehaviorStylePatch] par un composant.
enum BehaviorStyleHandling {
  /// Aucune prise en charge native : [ComponentStateBehavior] applique fond,
  /// bordure, texte, icône et opacité.
  none,

  /// Le composant applique lui-même `foregroundColor`, `fontSize`, `fontWeight`
  /// et `namedState` (ex. `SuperValue`).
  textOnly,

  /// La surface applique elle-même toutes les propriétés `ContainerStyle`
  /// (fond, bordure, rayon, élévation, opacité, remplissage, ombre, néon, `namedState`).
  surfaceOnly,

  /// Le composant applique lui-même fond, bordure, rayon, élévation, texte,
  /// icône et `namedState` (ex. `SuperAction`, `SuperIndicator`) ; seule l'opacité
  /// reste enveloppée par [ComponentStateBehavior].
  full,
}

BehaviorStyleHandling _mergeStyleHandling(
  BehaviorStyleHandling a,
  BehaviorStyleHandling b,
) {
  if (a == BehaviorStyleHandling.full || b == BehaviorStyleHandling.full) {
    return BehaviorStyleHandling.full;
  }
  if ((a == BehaviorStyleHandling.surfaceOnly &&
          b == BehaviorStyleHandling.textOnly) ||
      (a == BehaviorStyleHandling.textOnly &&
          b == BehaviorStyleHandling.surfaceOnly)) {
    return BehaviorStyleHandling.full;
  }
  if (a == BehaviorStyleHandling.none) return b;
  return a;
}

/// Portée héritée exposant les états et surcharges visuelles forcés par les
/// comportements (`bindState`, `setVisibility`, `setState`, `setStyle`).
class ComponentBehaviorStateScope extends InheritedWidget {
  const ComponentBehaviorStateScope({
    required this.invisible,
    required this.maintainSize,
    required this.readOnly,
    required this.disabled,
    this.styleOverride,
    this.styleDurationMs = 0,
    this.styleOwnerComponentId,
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

  /// Patch de style runtime actif sur le composant propriétaire [styleOwnerComponentId].
  final BehaviorStylePatch? styleOverride;

  /// Durée d'animation (ms) associée à [styleOverride].
  final int styleDurationMs;

  /// Identifiant du composant propriétaire de [styleOverride] (évite toute fuite
  /// vers des composants enfants imbriqués).
  final String? styleOwnerComponentId;

  /// Retourne la portée d'état de comportement la plus proche, ou `null`.
  static ComponentBehaviorStateScope? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ComponentBehaviorStateScope>();

  /// Retourne la portée d'état de comportement la plus proche sans enregistrer
  /// de dépendance de reconstruction (sûr dans les callbacks d'événements).
  static ComponentBehaviorStateScope? maybeReadOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ComponentBehaviorStateScope>();

  /// Indique si le contexte courant est marqué inactif par un comportement.
  static bool isDisabled(BuildContext context) =>
      maybeOf(context)?.disabled ?? false;

  /// Indique si le contexte courant est marqué en lecture seule par un comportement.
  static bool isReadOnly(BuildContext context) =>
      maybeOf(context)?.readOnly ?? false;

  /// Indique si le contexte courant est marqué invisible par un comportement.
  static bool isInvisible(BuildContext context) =>
      maybeOf(context)?.invisible ?? false;

  /// Retourne la surcharge de style runtime applicable à [componentId], ou `null`
  /// si le scope appartient à un autre composant parent.
  static BehaviorStylePatch? styleOverrideFor(
    BuildContext context,
    String componentId,
  ) {
    final scope = maybeOf(context);
    if (scope == null || scope.styleOwnerComponentId != componentId) {
      return null;
    }
    return scope.styleOverride;
  }

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
      disabled != oldWidget.disabled ||
      styleOverride != oldWidget.styleOverride ||
      styleDurationMs != oldWidget.styleDurationMs ||
      styleOwnerComponentId != oldWidget.styleOwnerComponentId;
}

/// Enveloppe réactive évaluant les [StateBindingAction] ainsi que les surcharges
/// runtime impératives (`setStyle`, `setVisibility`, `setState`) associées à
/// [componentId].
///
/// Supporte les contextes box et sliver ainsi que la déduplication des slots
/// imbriqués partageant le même [componentId].
class ComponentStateBehavior extends StatefulWidget {
  const ComponentStateBehavior({
    required this.componentId,
    required this.child,
    this.behaviors,
    this.sliver,
    this.styleHandling = BehaviorStyleHandling.none,
    super.key,
  });

  final String componentId;
  final Widget child;

  /// Une liste explicite remplace les comportements de l'apparence.
  final List<ComponentBehavior>? behaviors;

  /// À défaut, utilise le contexte de rendu du slot ([SliverSlotScope]).
  final bool? sliver;

  /// Indique quelles propriétés de [BehaviorStylePatch] sont déjà consommées
  /// nativement par l'enfant afin d'éviter toute double décoration.
  final BehaviorStyleHandling styleHandling;

  /// Actions [StateBindingAction] activées pour [componentId], hors mode édition.
  static List<StateBindingAction> actionsOf(
    BuildContext context,
    String componentId, {
    List<ComponentBehavior>? behaviors,
  }) {
    final items =
        behaviors ?? AppearanceScope.of(context).behaviorsFor(componentId);
    final candidates = [
      for (final behavior in items)
        if (behavior.enabled &&
            behavior.event == BehaviorEvent.onBinding &&
            behavior.action is StateBindingAction)
          behavior.action as StateBindingAction,
    ];
    if (candidates.isEmpty) return const [];
    if (StyleEditScope.controllerOf(context)?.value ?? false) {
      return const [];
    }
    return candidates;
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
      !identical(owners, oldWidget.owners) &&
      !mapEquals(owners, oldWidget.owners);
}

typedef _StateBehaviorOverride = ({
  List<ComponentBehavior>? behaviors,
  JsonRepositoryStore? store,
  JsonListScope? scope,
  BehaviorStyleHandling styleHandling,
});

class _ComponentStateBehaviorState extends State<ComponentStateBehavior> {
  final _childKey = GlobalKey();
  final _overrides = <Object, _StateBehaviorOverride>{};
  _ComponentStateBehaviorState? _overrideOwner;
  Map<String, _ComponentStateBehaviorState>? _cachedParentOwners;
  String? _cachedOwnerId;
  Map<String, _ComponentStateBehaviorState>? _cachedOwners;

  BehaviorRuntimeStateController? _runtimeController;
  Listenable? _runtimeListenable;
  String? _registeredRuntimeId;
  String? _registeredRuntimeScopeKey;
  bool _lastEffectiveVisible = true;
  bool _lastEffectiveDisabled = false;
  bool _lastEffectiveReadOnly = false;
  bool _hasActiveRuntimeStyle = false;

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

  void _runtimeOverrideChanged() {
    if (mounted) setState(() {});
  }

  void _syncRuntimeController(
    BehaviorRuntimeStateController? controller,
    String? scopeKey,
  ) {
    final listenable = controller?.listenableFor(widget.componentId);
    if (!identical(_runtimeListenable, listenable)) {
      _runtimeListenable?.removeListener(_runtimeOverrideChanged);
      _runtimeListenable = listenable;
      listenable?.addListener(_runtimeOverrideChanged);
    }
    if (!identical(_runtimeController, controller) ||
        _registeredRuntimeId != widget.componentId ||
        _registeredRuntimeScopeKey != scopeKey) {
      _runtimeController?.unregisterMountedInstance(this);
      _runtimeController = controller;
      _registeredRuntimeId = widget.componentId;
      _registeredRuntimeScopeKey = scopeKey;
      controller?.registerMountedInstance(
        token: this,
        componentId: widget.componentId,
        scopeKey: scopeKey,
        readEffectiveVisible: () => _lastEffectiveVisible,
        readEffectiveDisabled: () => _lastEffectiveDisabled,
        readEffectiveReadOnly: () => _lastEffectiveReadOnly,
      );
    }
  }

  void _detachRuntimeController() {
    _runtimeListenable?.removeListener(_runtimeOverrideChanged);
    _runtimeListenable = null;
    _runtimeController?.unregisterMountedInstance(this);
    _runtimeController = null;
    _registeredRuntimeId = null;
    _registeredRuntimeScopeKey = null;
  }

  void _detachOverride() {
    final owner = _overrideOwner;
    _overrideOwner = null;
    final removed = owner?._overrides.remove(this);
    if (removed != null &&
        owner!.mounted &&
        (removed.behaviors != null || owner._hasActiveRuntimeStyle)) {
      owner._markDirtyAndRebuild();
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
        identical(previous.scope, value.scope) &&
        previous.styleHandling == value.styleHandling) {
      return;
    }
    final behaviorsOrScopeChanged =
        (previous?.behaviors != null || value.behaviors != null) &&
        (!listEquals(previous?.behaviors, value.behaviors) ||
            !identical(previous?.store, value.store) ||
            !identical(previous?.scope, value.scope));
    owner._overrides[this] = value;
    if (behaviorsOrScopeChanged || owner._hasActiveRuntimeStyle) {
      owner._markDirtyAndRebuild();
    }
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
    _detachRuntimeController();
    _clearBindings();
    super.dispose();
  }

  Widget _applyRuntimeStyleWrapper(
    BuildContext context,
    Widget child, {
    required BehaviorStylePatch style,
    required int durationMs,
    required BehaviorStyleHandling handling,
    required bool isSliver,
  }) {
    final handlesSurface =
        handling == BehaviorStyleHandling.surfaceOnly ||
        handling == BehaviorStyleHandling.full;
    final handlesText =
        handling == BehaviorStyleHandling.textOnly ||
        handling == BehaviorStyleHandling.full;
    final handlesOpacity = handling == BehaviorStyleHandling.surfaceOnly;

    Widget content = child;
    final scheme = Theme.of(context).colorScheme;

    if (!isSliver && !handlesText && style.hasForegroundProperties) {
      final fgColor = resolveOptionalThemeColor(style.foregroundColor, scheme);
      if (fgColor != null) {
        content = IconTheme.merge(
          data: IconThemeData(color: fgColor),
          child: content,
        );
      }
      content = DefaultTextStyle.merge(
        style: TextStyle(
          color: fgColor,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
        ),
        child: content,
      );
    }

    if (!isSliver && !handlesSurface && style.hasSurfaceProperties) {
      final canAnimateSimpleBox =
          durationMs > 0 &&
          style.fill == null &&
          style.shadow == null &&
          style.neon == null &&
          style.elevation == null;
      if (canAnimateSimpleBox) {
        final bgColor = resolveOptionalThemeColor(
          style.backgroundColor,
          scheme,
        );
        final borderColor = resolveOptionalThemeColor(
          style.borderColor,
          scheme,
        );
        final borderWidth =
            style.borderWidth ?? (borderColor != null ? 1.0 : 0.0);
        content = AnimatedContainer(
          duration: Duration(milliseconds: durationMs),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: style.radius != null
                ? BorderRadius.circular(style.radius!)
                : null,
            border: borderWidth > 0
                ? Border.all(
                    color: borderColor ?? scheme.outlineVariant,
                    width: borderWidth,
                  )
                : null,
          ),
          child: content,
        );
      } else {
        final surfaceStyle = style
            .applyToContainerStyle(
              const ContainerStyle(color: Colors.transparent),
            )
            .copyWith(opacity: 1);
        content = StyledSurface(
          style: surfaceStyle,
          fallbackColor: Colors.transparent,
          borderColor: Colors.transparent,
          child: content,
        );
      }
    }

    if (!handlesOpacity && style.opacity != null) {
      final opacity = style.opacity!.clamp(0.0, 1.0);
      if (isSliver) {
        content = SliverOpacity(opacity: opacity, sliver: content);
      } else if (durationMs > 0) {
        content = AnimatedOpacity(
          opacity: opacity,
          duration: Duration(milliseconds: durationMs),
          child: content,
        );
      } else {
        content = Opacity(opacity: opacity, child: content);
      }
    }

    return content;
  }

  @override
  Widget build(BuildContext context) {
    final parentOwnerScope = context
        .dependOnInheritedWidgetOfExactType<_StateBehaviorOwnerScope>();
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    final owner = parentOwnerScope?.owners[widget.componentId];
    if (owner != null) {
      if (widget.behaviors != null ||
          widget.styleHandling != BehaviorStyleHandling.none) {
        _override(owner, (
          behaviors: widget.behaviors,
          store: JsonRepositoryScope.maybeOf(context),
          scope: JsonListScope.maybeOf(context),
          styleHandling: widget.styleHandling,
        ));
      } else {
        _detachOverride();
      }
      _detachRuntimeController();
      _clearBindings();
      return child;
    }
    _detachOverride();

    _StateBehaviorOverride? behaviorOverride;
    var effectiveStyleHandling = widget.styleHandling;
    for (final entry in _overrides.values) {
      effectiveStyleHandling = _mergeStyleHandling(
        effectiveStyleHandling,
        entry.styleHandling,
      );
      if (entry.behaviors != null) {
        behaviorOverride = entry;
      }
    }

    final actions = ComponentStateBehavior.actionsOf(
      context,
      widget.componentId,
      behaviors: behaviorOverride?.behaviors ?? widget.behaviors,
    );
    final store = behaviorOverride == null
        ? JsonRepositoryScope.maybeOf(context)
        : behaviorOverride.store;
    final scope = behaviorOverride == null
        ? JsonListScope.maybeOf(context)
        : behaviorOverride.scope;
    _sync(actions, scope, store);

    final editing = StyleEditScope.controllerOf(context)?.value ?? false;
    final runtimeController = BehaviorRuntimeStateScope.maybeOf(context);
    final runtimeScopeKey = ComponentRuntimeValueRegistry.scopeKeyOf(scope);
    _syncRuntimeController(runtimeController, runtimeScopeKey);
    final runtimeOverride = editing
        ? null
        : runtimeController?.overrideFor(
            widget.componentId,
            scopeKey: runtimeScopeKey,
          );

    final parentStateScope = ComponentBehaviorStateScope.maybeOf(context);
    final boundInvisible = _activeStates.contains(BehaviorBoundState.invisible);
    final boundDisabled = _activeStates.contains(BehaviorBoundState.disabled);
    final boundReadOnly = _activeStates.contains(BehaviorBoundState.readOnly);

    final localInvisible = runtimeOverride?.visible != null
        ? !runtimeOverride!.visible!
        : boundInvisible;
    final localMaintainSize = runtimeOverride?.visible != null
        ? (!runtimeOverride!.visible! && runtimeOverride.maintainSize)
        : (boundInvisible && _maintainSize);
    final localDisabled = runtimeOverride?.disabled ?? boundDisabled;
    final localReadOnly = runtimeOverride?.readOnly ?? boundReadOnly;
    final localStyle = runtimeOverride?.style;
    final localStyleDurationMs = runtimeOverride?.styleDurationMs ?? 0;

    final effectiveInvisible =
        (parentStateScope?.invisible ?? false) || localInvisible;
    final effectiveMaintainSize = localInvisible
        ? localMaintainSize
        : (parentStateScope?.maintainSize ?? false);
    final effectiveDisabled =
        (parentStateScope?.disabled ?? false) || localDisabled;
    final effectiveReadOnly =
        (parentStateScope?.readOnly ?? false) || localReadOnly;

    _lastEffectiveVisible = !effectiveInvisible;
    _lastEffectiveDisabled = effectiveDisabled;
    _lastEffectiveReadOnly = effectiveReadOnly;
    _hasActiveRuntimeStyle = localStyle != null && !localStyle.isEmpty;

    final isSliver = widget.sliver ?? SliverSlotScope.isSliver(context);
    Widget content = child;

    if (localStyle != null && !localStyle.isEmpty) {
      content = _applyRuntimeStyleWrapper(
        context,
        content,
        style: localStyle,
        durationMs: localStyleDurationMs,
        handling: effectiveStyleHandling,
        isSliver: isSliver,
      );
    }

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
              maintainSize: localMaintainSize,
              maintainAnimation: localMaintainSize,
              maintainState: localMaintainSize,
              sliver: content,
            )
          : Visibility(
              visible: false,
              maintainSize: localMaintainSize,
              maintainAnimation: localMaintainSize,
              maintainState: localMaintainSize,
              child: content,
            );
    }

    final parentOwners = parentOwnerScope?.owners;
    var owners = _cachedOwners;
    if (owners == null ||
        !identical(parentOwners, _cachedParentOwners) ||
        _cachedOwnerId != widget.componentId) {
      _cachedParentOwners = parentOwners;
      _cachedOwnerId = widget.componentId;
      owners = Map<String, _ComponentStateBehaviorState>.unmodifiable({
        ...?parentOwners,
        widget.componentId: this,
      });
      _cachedOwners = owners;
    }

    return _StateBehaviorOwnerScope(
      owners: owners,
      child: ComponentBehaviorStateScope(
        invisible: effectiveInvisible,
        maintainSize: effectiveMaintainSize,
        readOnly: effectiveReadOnly,
        disabled: effectiveDisabled,
        styleOverride: localStyle,
        styleDurationMs: localStyleDurationMs,
        styleOwnerComponentId: localStyle != null ? widget.componentId : null,
        child: content,
      ),
    );
  }
}
