/// Observation unifiée des événements impératifs de pointeur, survol et cycle
/// de vie ([BehaviorEventListener]) sans concurrence avec les gestes natifs.
///
/// Prend en charge `onTap`, `onDoubleTap`, `onLongPress`, `onHoverEnter`,
/// `onHoverExit` et `onMount`, et délègue systématiquement l'exécution à
/// [BehaviorDispatcher.dispatch] afin d'appliquer les validateurs, la garde
/// d'édition, la garde d'état désactivé/invisible et l'anti-réentrance.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../services/behaviors/behavior_dispatcher.dart';
import '../../services/events/super_event_bus.dart';
import '../editing/slots/editor_selection_region.dart';
import '../editing/slots/editor_slot.dart' show StyleEditScope;
import 'component_state_behavior.dart';

/// Observe les événements impératifs d'un composant sans absorber focus,
/// sélection, bascule ou défilement des widgets natifs enfants.
class BehaviorEventListener extends StatefulWidget {
  /// Crée un écouteur d'événements impératifs autour de [child].
  const BehaviorEventListener({
    required this.componentId,
    required this.componentType,
    required this.behaviors,
    required this.child,
    this.readData,
    this.sliver = false,
    this.handlesTapExternally = false,
    super.key,
  });

  /// Identifiant technique du composant.
  final String componentId;

  /// Type du composant transmis aux données d'exécution.
  final String componentType;

  /// Liste des comportements impératifs à observer pour ce composant.
  final List<ComponentBehavior> behaviors;

  /// Lecteur paresseux des données runtime de l'instance.
  final Map<String, Object?> Function()? readData;

  /// Indique si le composant s'insère dans un contexte sliver.
  final bool sliver;

  /// Lorsque `true`, `onTap` est déjà géré par le widget enfant (ex. `SuperAction`) :
  /// cet écouteur n'exécute pas `onTap` mais revendique tout de même l'événement
  /// pointeur pour empêcher un slot ancêtre de même ID de le déclencher en double.
  final bool handlesTapExternally;

  /// Sous-arbre enfant observé.
  final Widget child;

  @override
  State<BehaviorEventListener> createState() => _BehaviorEventListenerState();
}

class _BehaviorEventListenerScope extends InheritedWidget {
  const _BehaviorEventListenerScope({
    required this.owners,
    required super.child,
  });

  final Map<String, _BehaviorEventListenerState> owners;

  @override
  bool updateShouldNotify(_BehaviorEventListenerScope oldWidget) =>
      !identical(owners, oldWidget.owners) &&
      !mapEquals(owners, oldWidget.owners);
}

class _BehaviorEventListenerState extends State<BehaviorEventListener> {
  static final _targets = Expando<Set<String>>();
  final Set<_BehaviorEventListenerState> _innerDelegates =
      <_BehaviorEventListenerState>{};
  _BehaviorEventListenerState? _delegateOwner;
  Map<String, _BehaviorEventListenerState>? _cachedParentOwners;
  String? _cachedOwnerId;
  Map<String, _BehaviorEventListenerState>? _cachedOwners;

  PointerDownEvent? _down;
  Map<String, Object?>? _before;
  PointerDownEvent? _firstDown;
  Duration? _firstUp;
  Map<String, Object?>? _firstBefore;
  Timer? _longPressTimer;
  bool _longPressFired = false;
  bool _mountDispatched = false;
  bool _mountScheduled = false;
  int _generation = 0;

  bool get _hasTap =>
      !widget.handlesTapExternally &&
      BehaviorDispatcher.hasImperativeBehavior(
        widget.behaviors,
        BehaviorEvent.onTap,
      );

  bool get _hasDoubleTap => BehaviorDispatcher.hasImperativeBehavior(
    widget.behaviors,
    BehaviorEvent.onDoubleTap,
  );

  bool get _hasLongPress => BehaviorDispatcher.hasImperativeBehavior(
    widget.behaviors,
    BehaviorEvent.onLongPress,
  );

  bool get _hasPointerGesture => _hasTap || _hasDoubleTap || _hasLongPress;

  bool get _hasHoverEnter => BehaviorDispatcher.hasImperativeBehavior(
    widget.behaviors,
    BehaviorEvent.onHoverEnter,
  );

  bool get _hasHoverExit => BehaviorDispatcher.hasImperativeBehavior(
    widget.behaviors,
    BehaviorEvent.onHoverExit,
  );

  bool get _hasMount => BehaviorDispatcher.hasImperativeBehavior(
    widget.behaviors,
    BehaviorEvent.onMount,
  );

  Map<String, Object?> _read() =>
      immutableEventJson(widget.readData?.call() ?? const {});

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _cancel() {
    _generation++;
    _cancelLongPressTimer();
    _longPressFired = false;
    _down = null;
    _before = null;
    _firstDown = null;
    _firstUp = null;
    _firstBefore = null;
  }

  void _attachDelegateOwner(_BehaviorEventListenerState? owner) {
    if (identical(_delegateOwner, owner)) return;
    _delegateOwner?._innerDelegates.remove(this);
    _delegateOwner = owner;
    owner?._innerDelegates.add(this);
  }

  void _scheduleMountIfNeeded() {
    if (_mountDispatched || _mountScheduled || !_hasMount) return;
    _mountScheduled = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mountScheduled = false;
      if (!mounted ||
          generation != _generation ||
          _mountDispatched ||
          !_hasMount ||
          _innerDelegates.isNotEmpty) {
        return;
      }
      if (StyleEditScope.maybeReadOf(context)?.value ?? false) {
        return;
      }
      final stateScope = ComponentBehaviorStateScope.maybeReadOf(context);
      if (stateScope != null && (stateScope.disabled || stateScope.invisible)) {
        return;
      }
      _mountDispatched = true;
      final snapshot = _read();
      unawaited(
        BehaviorDispatcher.dispatch(
          context,
          componentId: widget.componentId,
          componentType: widget.componentType,
          event: BehaviorEvent.onMount,
          data: snapshot,
          behaviors: List<ComponentBehavior>.of(widget.behaviors),
        ),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleMountIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleMountIfNeeded();
  }

  @override
  void didUpdateWidget(BehaviorEventListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.componentId != oldWidget.componentId) {
      _mountDispatched = false;
      _cancel();
    } else if (!_hasPointerGesture) {
      _cancel();
    }
    _scheduleMountIfNeeded();
  }

  @override
  void dispose() {
    _attachDelegateOwner(null);
    _innerDelegates.clear();
    _cancel();
    super.dispose();
  }

  void _onDown(PointerDownEvent event) {
    if (!_hasPointerGesture && !widget.handlesTapExternally) return;
    if (event.buttons != kPrimaryButton) {
      if (_hasPointerGesture) _cancel();
      return;
    }
    if (_hasPointerGesture && _down != null) {
      _cancel();
      return;
    }
    PointerEvent original = event;
    while (original.original != null) {
      original = original.original!;
    }
    final targets = _targets[original] ??= <String>{};
    // Equivalent nested slots represent the same technical component.
    if (!targets.add(widget.componentId)) return;
    if (!_hasPointerGesture) return;

    _down = event;
    _before = _read();
    _longPressFired = false;
    _cancelLongPressTimer();

    if (_hasLongPress) {
      final generation = _generation;
      final before = _before!;
      final componentId = widget.componentId;
      final componentType = widget.componentType;
      final behaviors = List<ComponentBehavior>.of(widget.behaviors);
      _longPressTimer = Timer(kLongPressTimeout, () {
        if (!mounted || generation != _generation || _down == null) return;
        _longPressFired = true;
        _longPressTimer = null;
        _down = null;
        _before = null;
        _firstDown = null;
        _firstUp = null;
        _firstBefore = null;
        final after = _read();
        unawaited(
          BehaviorDispatcher.dispatch(
            context,
            componentId: componentId,
            componentType: componentType,
            event: BehaviorEvent.onLongPress,
            data: {
              ...after,
              if (before.containsKey('value')) 'previousValue': before['value'],
            },
            behaviors: behaviors,
          ),
        );
      });
    }
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down != null &&
        down.pointer == event.pointer &&
        (event.position - down.position).distance > kTouchSlop) {
      _cancel();
    }
  }

  void _onUp(PointerUpEvent event) {
    _cancelLongPressTimer();
    if (_longPressFired) {
      _longPressFired = false;
      return;
    }
    final down = _down;
    final before = _before;
    if (down == null || before == null || down.pointer != event.pointer) return;
    if ((event.position - down.position).distance > kTouchSlop ||
        event.timeStamp - down.timeStamp > kLongPressTimeout) {
      _cancel();
      return;
    }
    _down = null;
    _before = null;
    final firstDown = _firstDown;
    final firstUp = _firstUp;
    final firstBefore = _firstBefore;
    final interval = firstUp == null ? null : down.timeStamp - firstUp;
    final isDouble =
        firstDown != null &&
        firstBefore != null &&
        interval != null &&
        interval >= kDoubleTapMinTime &&
        interval <= kDoubleTapTimeout &&
        firstDown.kind == down.kind &&
        firstDown.device == down.device &&
        (firstDown.position - down.position).distance <= kDoubleTapSlop;
    if (isDouble) {
      _firstDown = null;
      _firstUp = null;
      _firstBefore = null;
    } else {
      _firstDown = down;
      _firstUp = event.timeStamp;
      _firstBefore = before;
    }

    final triggers = <BehaviorEvent>[
      if (_hasTap) BehaviorEvent.onTap,
      if (isDouble && _hasDoubleTap) BehaviorEvent.onDoubleTap,
    ];
    if (triggers.isEmpty) return;

    final generation = _generation;
    final componentId = widget.componentId;
    final componentType = widget.componentType;
    final behaviors = List<ComponentBehavior>.of(widget.behaviors);
    // Pointer listeners run before the child's tap callbacks.
    scheduleMicrotask(() async {
      if (!mounted || generation != _generation) return;
      final after = _read();
      for (final trigger in triggers) {
        if (!mounted || generation != _generation) return;
        final previous = trigger == BehaviorEvent.onDoubleTap
            ? firstBefore!
            : before;
        await BehaviorDispatcher.dispatch(
          context,
          componentId: componentId,
          componentType: componentType,
          event: trigger,
          data: {
            ...after,
            if (previous.containsKey('value'))
              'previousValue': previous['value'],
          },
          behaviors: behaviors,
        );
      }
    });
  }

  void _onHoverEnter(PointerEnterEvent event) {
    if (!_hasHoverEnter || _innerDelegates.isNotEmpty) return;
    final snapshot = _read();
    unawaited(
      BehaviorDispatcher.dispatch(
        context,
        componentId: widget.componentId,
        componentType: widget.componentType,
        event: BehaviorEvent.onHoverEnter,
        data: snapshot,
        behaviors: List<ComponentBehavior>.of(widget.behaviors),
      ),
    );
  }

  void _onHoverExit(PointerExitEvent event) {
    if (!_hasHoverExit || _innerDelegates.isNotEmpty) return;
    final snapshot = _read();
    unawaited(
      BehaviorDispatcher.dispatch(
        context,
        componentId: widget.componentId,
        componentType: widget.componentType,
        event: BehaviorEvent.onHoverExit,
        data: snapshot,
        behaviors: List<ComponentBehavior>.of(widget.behaviors),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parent = context
        .dependOnInheritedWidgetOfExactType<_BehaviorEventListenerScope>();
    final owner = parent?.owners[widget.componentId];
    _attachDelegateOwner(owner);

    final cursor = _hasPointerGesture
        ? SystemMouseCursors.click
        : MouseCursor.defer;
    final observePointer = _hasPointerGesture || widget.handlesTapExternally;

    final Widget wrapped = widget.sliver
        ? SliverPointerRegion(
            cursor: cursor,
            onEnter: _hasHoverEnter ? _onHoverEnter : null,
            onExit: _hasHoverExit ? _onHoverExit : null,
            onPointerDown: observePointer ? _onDown : null,
            onPointerMove: _hasPointerGesture ? _onMove : null,
            onPointerUp: _hasPointerGesture ? _onUp : null,
            onPointerCancel: _hasPointerGesture ? (_) => _cancel() : null,
            child: widget.child,
          )
        : MouseRegion(
            cursor: cursor,
            onEnter: _hasHoverEnter ? _onHoverEnter : null,
            onExit: _hasHoverExit ? _onHoverExit : null,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: observePointer ? _onDown : null,
              onPointerMove: _hasPointerGesture ? _onMove : null,
              onPointerUp: _hasPointerGesture ? _onUp : null,
              onPointerCancel: _hasPointerGesture ? (_) => _cancel() : null,
              child: widget.child,
            ),
          );

    final parentOwners = parent?.owners;
    var owners = _cachedOwners;
    if (owners == null ||
        !identical(parentOwners, _cachedParentOwners) ||
        _cachedOwnerId != widget.componentId) {
      _cachedParentOwners = parentOwners;
      _cachedOwnerId = widget.componentId;
      owners = Map<String, _BehaviorEventListenerState>.unmodifiable({
        ...?parentOwners,
        widget.componentId: this,
      });
      _cachedOwners = owners;
    }

    return _BehaviorEventListenerScope(owners: owners, child: wrapped);
  }
}
