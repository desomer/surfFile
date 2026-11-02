// Tailles de côtés liées à un repository ([ZoneSizeBindingAction]) et animées.
//
// Les tailles animées remplacent celles de la configuration au layout
// uniquement : elles ne sont jamais enregistrées.
part of 'super_layout.dart';

/// Taille animée d'un côté, exprimée dans l'unité de son action.
class _ZoneSizeTrack {
  _ZoneSizeTrack(TickerProvider vsync, this.action)
    : controller = AnimationController(vsync: vsync, value: 1);

  ZoneSizeBindingAction action;
  final AnimationController controller;
  double? _begin;
  double? _end;

  bool get hasValue => _end != null;
  bool get animating => controller.isAnimating;

  /// Valeur courante dans l'unité de [action], ou `null` sans valeur liée.
  double? get value {
    final begin = _begin;
    final end = _end;
    if (begin == null || end == null) return null;
    if (!animating) return end;
    return lerpDouble(
      begin,
      end,
      action.curve.curve.transform(controller.value),
    );
  }

  /// Fermé : valeur nulle atteinte, l'animation éventuelle est terminée.
  bool get closed => !animating && (_end ?? 1) <= 0;

  /// Plus grande des tailles de début et de fin pendant une animation : le
  /// contenu y garde sa taille et est rogné (effet tiroir).
  double? get drawerValue => animating && _begin != null && _end != null
      ? math.max(_begin!, _end!)
      : null;

  /// Retourne `true` si l'état fermé / animé change.
  bool setTarget(double? target, {required bool animate}) {
    final wasClosed = closed;
    final wasAnimating = animating;
    final hadValue = hasValue;
    if (target == null) {
      controller.value = 1;
      _begin = _end = null;
    } else if (!animate || _end == null || action.durationMs == 0) {
      if (target == _end && !animating) return false;
      controller.value = 1;
      _begin = _end = target;
    } else {
      if (target == _end) return false;
      _begin = value;
      _end = target;
      controller.duration = action.duration;
      controller.forward(from: 0);
    }
    return wasClosed != closed ||
        wasAnimating != animating ||
        hadValue != hasValue;
  }

  void dispose() => controller.dispose();
}

/// Notifie à chaque image d'une animation de taille.
class _ZoneSizeFrames extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Observe les [ZoneSizeBindingAction] d'un layout et anime leurs côtés.
///
/// Notifie ses écouteurs quand l'ensemble des côtés liés, leur état fermé ou
/// le début / la fin d'une animation change ; [frames] notifie à chaque image
/// d'une animation (relayout seul, sans reconstruction).
class _ZoneSizeBindings extends ChangeNotifier {
  _ZoneSizeBindings(this._vsync);

  final TickerProvider _vsync;
  final _tracks = <SuperLayoutZone, _ZoneSizeTrack>{};
  final frames = _ZoneSizeFrames();

  List<ZoneSizeBindingAction> _actions = const [];
  JsonRepositoryStore? _store;
  String? _scopeRepositoryId;
  List<int> _scopeIndices = const [];
  String? _scopeNodePath;
  bool _dirty = true;
  int _generation = 0;
  List<JsonArrayBinding> _selections = const [];
  Map<SuperLayoutZone, JsonTextBinding> _resolved = const {};
  String? _lastError;
  bool _disposed = false;

  /// Côtés pilotés par une action active.
  Set<SuperLayoutZone> get boundSides => _tracks.keys.toSet();

  /// Côtés liés ayant une valeur : leur taille remplace celle de la config.
  Set<SuperLayoutZone> get overriddenSides => {
    for (final entry in _tracks.entries)
      if (entry.value.hasValue) entry.key,
  };

  /// Côtés liés dont la valeur atteinte est nulle.
  Set<SuperLayoutZone> get closedSides => {
    for (final entry in _tracks.entries)
      if (entry.value.closed) entry.key,
  };

  bool get isEmpty => _tracks.isEmpty;

  /// Synchronise les actions actives ; appelé pendant la construction, sans
  /// notification pour les changements synchrones.
  void sync(
    List<ComponentBehavior> behaviors,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    final byZone = <SuperLayoutZone, ZoneSizeBindingAction>{
      for (final behavior in behaviors)
        if (behavior.enabled && behavior.action is ZoneSizeBindingAction)
          (behavior.action as ZoneSizeBindingAction).zone:
              behavior.action as ZoneSizeBindingAction,
    };
    final actions = byZone.values.toList();
    final sameContext =
        !_dirty &&
        listEquals(actions, _actions) &&
        identical(store, _store) &&
        _scopeRepositoryId == scope?.repositoryId &&
        _scopeNodePath == scope?.nodePath &&
        listEquals(_scopeIndices, scope?.indices ?? const []);
    if (sameContext) return;
    _dirty = false;
    _actions = actions;
    _scopeRepositoryId = scope?.repositoryId;
    _scopeNodePath = scope?.nodePath;
    _scopeIndices = List.of(scope?.indices ?? const []);
    if (!identical(store, _store)) {
      _store?.removeListener(_storeChanged);
      _store?.unregisterBindings(this);
      store?.addListener(_storeChanged);
      _store = store;
    }

    for (final zone in _tracks.keys.toList()) {
      final next = byZone[zone];
      final track = _tracks[zone]!;
      if (next == null) {
        track.controller.removeListener(_tick);
        track.controller.removeStatusListener(_status);
        track.dispose();
        _tracks.remove(zone);
      } else if (next.unit != track.action.unit ||
          next.binding != track.action.binding) {
        track.action = next;
        track.setTarget(null, animate: false);
      } else {
        track.action = next;
      }
    }
    for (final entry in byZone.entries) {
      _tracks.putIfAbsent(entry.key, () {
        final track = _ZoneSizeTrack(_vsync, entry.value);
        track.controller
          ..addListener(_tick)
          ..addStatusListener(_status);
        return track;
      });
    }

    store?.registerBindings(this, [
      for (final action in actions)
        action.binding.repositoryId ?? scope?.repositoryId,
    ]);
    final selections = <JsonArrayBinding>{};
    final resolved = <SuperLayoutZone, JsonTextBinding>{};
    for (final entry in byZone.entries) {
      try {
        final result = JsonListScope.resolveSelected(
          entry.value.binding,
          scope,
          store,
        );
        selections.addAll(result.arrays);
        if (result.binding != null) resolved[entry.key] = result.binding!;
      } on FormatException catch (error) {
        _report(error.message);
      }
    }
    _listenSelections(selections.toList());
    _resolved = resolved;
    for (final zone in _tracks.keys) {
      final binding = resolved[zone];
      if (binding == null) {
        _tracks[zone]!.setTarget(null, animate: false);
        continue;
      }
      final cached = store?.peekAttribute(binding);
      if (cached != null) {
        _apply(zone, cached.value, animate: _tracks[zone]!.hasValue);
      }
    }
    _load();
  }

  void _listenSelections(List<JsonArrayBinding> selections) {
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
    if (!_disposed) notifyListeners();
  }

  void _storeChanged() => _load();

  void _load() {
    final store = _store;
    if (store == null || _resolved.isEmpty) return;
    final generation = ++_generation;
    final bindings = Map.of(_resolved);
    unawaited(() async {
      for (final entry in bindings.entries) {
        Object? value;
        try {
          value = (await store.readAttribute(entry.value)).value;
        } on FormatException catch (error) {
          if (_disposed || generation != _generation) return;
          _report(error.message);
          continue;
        } on FileSystemException {
          if (_disposed || generation != _generation) return;
          _report('Impossible de lire le repository lié.');
          continue;
        }
        if (_disposed || generation != _generation) return;
        final track = _tracks[entry.key];
        if (track == null) continue;
        if (_apply(entry.key, value, animate: track.hasValue)) {
          notifyListeners();
        } else {
          frames.tick();
        }
      }
    }());
  }

  /// Applique une valeur lue ; retourne `true` si l'état structurel change.
  bool _apply(SuperLayoutZone zone, Object? raw, {required bool animate}) {
    final track = _tracks[zone];
    if (track == null) return false;
    final number = switch (raw) {
      num value => value.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (raw != null && (number == null || !number.isFinite)) {
      _report(
        'Taille de la zone ${zone.label} : « $raw » n’est pas un nombre.',
      );
    }
    final target = number == null || !number.isFinite
        ? null
        : math.max(0.0, number);
    return track.setTarget(target, animate: animate);
  }

  void _report(String message) {
    if (message == _lastError) return;
    _lastError = message;
    _store?.reportBindingError(message);
  }

  void _tick() => frames.tick();

  void _status(AnimationStatus status) {
    if (!_disposed) notifyListeners();
  }

  /// Épaisseur en pixels de [track] pour une valeur dans son unité.
  static double? _pixels(_ZoneSizeTrack track, double? value, Size basis) {
    if (value == null) return null;
    if (track.action.unit == SlotSizeUnit.pixels) return value;
    final extent = switch (track.action.zone) {
      SuperLayoutZone.north || SuperLayoutZone.south => basis.height,
      _ => basis.width,
    };
    return extent.isFinite ? value / 100 * extent : null;
  }

  /// Épaisseur courante de [zone] en pixels, ou `null` sans override.
  double? extentOf(SuperLayoutZone zone, Size basis) {
    final track = _tracks[zone];
    return track == null ? null : _pixels(track, track.value, basis);
  }

  /// Épaisseur de mise en page du contenu de [zone] pendant une animation.
  double? drawerExtentOf(SuperLayoutZone zone, Size basis) {
    final track = _tracks[zone];
    return track == null ? null : _pixels(track, track.drawerValue, basis);
  }

  /// [config] avec les côtés liés en taille fixe (ou fermés) ; [basis] est la
  /// taille du layout pour les pourcentages.
  SuperLayoutConfig apply(SuperLayoutConfig config, Size basis) {
    if (_tracks.isEmpty) return config;
    var autoSides = config.autoSides;
    var collapsed = config.collapsedSides;
    double? north, south, west, east;
    for (final MapEntry(key: zone, value: track) in _tracks.entries) {
      if (!config.hasSide(zone)) continue;
      final extent = _pixels(track, track.value, basis);
      if (extent == null) continue;
      autoSides = {...autoSides}..remove(zone);
      collapsed = {...collapsed}..remove(zone);
      if (track.closed) {
        collapsed = {...collapsed, zone: config.sizeOf(zone)};
      }
      switch (zone) {
        case SuperLayoutZone.north:
          north = extent;
        case SuperLayoutZone.south:
          south = extent;
        case SuperLayoutZone.west:
          west = extent;
        default:
          east = extent;
      }
    }
    return config.copyWith(
      autoSides: autoSides,
      collapsedSides: collapsed,
      northSize: north,
      southSize: south,
      westSize: west,
      eastSize: east,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _listenSelections(const []);
    _store?.removeListener(_storeChanged);
    _store?.unregisterBindings(this);
    for (final track in _tracks.values) {
      track.dispose();
    }
    _tracks.clear();
    frames.dispose();
    super.dispose();
  }
}

/// Garde le contenu d'un côté animé à sa plus grande taille et le fait glisser :
/// la zone s'ouvre ou se ferme comme un tiroir, sans réagencer son contenu à
/// chaque image.
class _ZoneDrawer extends StatelessWidget {
  const _ZoneDrawer({
    required this.zone,
    required this.bindings,
    required this.basis,
    required this.child,
  });

  final SuperLayoutZone zone;
  final _ZoneSizeBindings bindings;
  final Size basis;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: bindings.frames,
    child: child,
    builder: (context, child) {
      final extent = bindings.drawerExtentOf(zone, basis);
      final vertical =
          zone == SuperLayoutZone.north || zone == SuperLayoutZone.south;
      return ClipRect(
        clipBehavior: extent == null ? Clip.none : Clip.hardEdge,
        child: _ZoneDrawerBox(
          extent: extent,
          vertical: vertical,
          // Le bord intérieur suit la zone ; le contenu glisse depuis l'extérieur.
          alignment: switch (zone) {
            SuperLayoutZone.west => Alignment.centerRight,
            SuperLayoutZone.east => Alignment.centerLeft,
            SuperLayoutZone.north => Alignment.bottomCenter,
            _ => Alignment.topCenter,
          },
          child: child,
        ),
      );
    },
  );
}

/// Sans [extent], transmet les contraintes telles quelles ; sinon impose
/// [extent] sur l'axe du côté et aligne l'enfant dans sa propre taille.
class _ZoneDrawerBox extends SingleChildRenderObjectWidget {
  const _ZoneDrawerBox({
    required this.extent,
    required this.vertical,
    required this.alignment,
    super.child,
  });

  final double? extent;
  final bool vertical;
  final Alignment alignment;

  @override
  _RenderZoneDrawerBox createRenderObject(BuildContext context) =>
      _RenderZoneDrawerBox(extent, vertical, alignment);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderZoneDrawerBox renderObject,
  ) => renderObject
    ..extent = extent
    ..vertical = vertical
    ..alignment = alignment;
}

class _RenderZoneDrawerBox extends RenderShiftedBox {
  _RenderZoneDrawerBox(this._extent, this._vertical, this._alignment)
    : super(null);

  double? _extent;
  set extent(double? value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsLayout();
  }

  bool _vertical;
  set vertical(bool value) {
    if (value == _vertical) return;
    _vertical = value;
    markNeedsLayout();
  }

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) {
    final extent = _extent;
    if (extent == null) return constraints;
    return _vertical
        ? constraints.copyWith(minHeight: extent, maxHeight: extent)
        : constraints.copyWith(minWidth: extent, maxWidth: extent);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    if (_extent == null) return child.getDryLayout(constraints);
    return constraints.constrain(
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
    (child.parentData! as BoxParentData).offset = _alignment.alongOffset(
      (size - child.size) as Offset,
    );
  }
}
