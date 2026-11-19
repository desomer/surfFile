/// Fond animé glissant d'une ligne à l'autre dans les collections (liste,
/// arbre, tableau) pour les états survolé et sélectionné.
///
/// Une [SlidingIndicatorMotion] calcule le rectangle courant de l'indicateur,
/// exprimé dans le repère du contenu défilant. Chaque ligne place un
/// [SlidingIndicatorUnderlay] à l'intérieur de sa surface, entre son fond par
/// défaut et son contenu : l'underlay y peint la portion de l'indicateur qui
/// recouvre la ligne. L'indicateur reste ainsi au-dessus du fond (même opaque)
/// de la ligne et toujours sous son contenu, tout en glissant entre les lignes.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Position et opacité animées d'un indicateur de ligne (survol ou
/// sélection), partagées par toutes les lignes d'une collection.
///
/// [show] fixe la cible : l'indicateur apparaît en fondu sur la première
/// cible, glisse vers les suivantes puis disparaît en fondu sans cible. Les
/// écouteurs sont notifiés pendant les callbacks de frame, jamais pendant la
/// construction, afin que les lignes puissent se remettre en page sans risque.
class SlidingIndicatorMotion extends ChangeNotifier {
  /// Crée une animation d'indicateur pilotée par [vsync].
  SlidingIndicatorMotion({
    required TickerProvider vsync,
    required Duration slideDuration,
    this.slideCurve = Curves.easeOutCubic,
    this.fadeDuration = const Duration(milliseconds: 150),
    this.fadeCurve = Curves.easeOut,
    this.hideDelay = Duration.zero,
  }) : _slide = AnimationController(
         vsync: vsync,
         duration: slideDuration,
         value: 1,
       ),
       _fade = AnimationController(vsync: vsync, duration: fadeDuration) {
    _slide.addListener(_tick);
    _fade.addListener(_tick);
  }

  /// Courbe du glissement entre deux lignes.
  final Curve slideCurve;

  /// Durée des fondus d'apparition et de disparition.
  final Duration fadeDuration;

  /// Courbe des fondus d'apparition et de disparition.
  final Curve fadeCurve;

  /// Délai pendant lequel l'indicateur reste opaque après la perte de sa
  /// cible, afin de glisser vers une cible voisine (espace entre lignes).
  final Duration hideDelay;

  final AnimationController _slide;
  final AnimationController _fade;
  Rect _from = Rect.zero;
  Rect _to = Rect.zero;
  bool _visible = false;
  bool _silent = false;
  bool _disposed = false;
  int? _notifyCallbackId;

  /// Rectangle courant de l'indicateur dans le repère du contenu.
  Rect get rect => Rect.lerp(_from, _to, slideCurve.transform(_slide.value))!;

  /// Opacité courante de l'indicateur, entre 0 et 1.
  double get opacity => _fade.value.clamp(0.0, 1.0);

  /// Vrai lorsque l'indicateur a une cible (il peut encore apparaître).
  bool get visible => _visible;

  /// Cible courante (ou dernière cible avant disparition) de l'indicateur.
  Rect get target => _to;

  /// Durée du glissement entre deux lignes.
  Duration get slideDuration => _slide.duration!;

  /// Affiche l'indicateur sur [target], ou le masque si [target] est nul.
  ///
  /// Peut être appelé pendant la construction : les lignes sont notifiées à
  /// la frame suivante.
  void show(Rect? target) {
    if (_disposed) return;
    if (target != null && !target.isFinite) target = null;
    _silent = true;
    try {
      if (target == null) {
        if (!_visible) return;
        _visible = false;
        _hide();
      } else if (!_visible) {
        _visible = true;
        if (_fade.value <= 0) {
          _from = target;
          _to = target;
          _slide.value = 1;
        } else if (_moved(target, _to)) {
          // Still fading out: slide from where the indicator stands.
          _from = rect;
          _to = target;
          _slide.forward(from: 0);
        }
        _fade.animateTo(1, duration: fadeDuration, curve: fadeCurve);
      } else if (_moved(target, _to)) {
        _from = rect;
        _to = target;
        _slide.forward(from: 0);
      } else {
        return;
      }
    } finally {
      _silent = false;
    }
    _scheduleNotify();
  }

  static bool _moved(Rect a, Rect b) =>
      (a.left - b.left).abs() > 0.5 ||
      (a.top - b.top).abs() > 0.5 ||
      (a.right - b.right).abs() > 0.5 ||
      (a.bottom - b.bottom).abs() > 0.5;

  /// Fond l'indicateur après [hideDelay], sans minuterie : la courbe garde
  /// l'opacité constante pendant le délai.
  void _hide() {
    final total = hideDelay + fadeDuration;
    final delay = total.inMicroseconds == 0
        ? 0.0
        : hideDelay.inMicroseconds / total.inMicroseconds;
    _fade.animateTo(
      0,
      duration: total,
      curve: delay <= 0 ? fadeCurve : Interval(delay, 1, curve: fadeCurve),
    );
  }

  void _tick() {
    if (!_silent) notifyListeners();
  }

  void _scheduleNotify() {
    if (_notifyCallbackId != null) return;
    _notifyCallbackId = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _notifyCallbackId = null;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final id = _notifyCallbackId;
    if (id != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _notifyCallbackId = null;
    }
    _slide.dispose();
    _fade.dispose();
    super.dispose();
  }
}

/// Partage les animations d'indicateurs d'une collection avec ses lignes.
class SlidingIndicatorScope extends InheritedWidget {
  /// Crée une portée d'indicateurs glissants.
  const SlidingIndicatorScope({
    required this.hover,
    required this.selection,
    required this.contentOffsetOf,
    required super.child,
    super.key,
  });

  /// Animation de l'indicateur de survol.
  final SlidingIndicatorMotion hover;

  /// Animation de l'indicateur de sélection, peint au-dessus du survol.
  final SlidingIndicatorMotion selection;

  /// Position d'une boîte dans le repère du contenu de la collection (celui
  /// des rectangles passés à [SlidingIndicatorMotion.show]), ou `null` si
  /// elle est inconnue. Doit être stable (méthode d'un `State`).
  final Offset? Function(RenderBox box) contentOffsetOf;

  /// Portée la plus proche, ou `null`.
  static SlidingIndicatorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlidingIndicatorScope>();

  /// Position de [box] relative à [ancestor], ou `null` si [box] n'est pas
  /// (encore) mis en page sous [ancestor]. Traverse aussi les slivers.
  static Offset? offsetWithin(RenderBox box, RenderObject? ancestor) {
    if (ancestor == null || !ancestor.attached) return null;
    RenderObject? current = box;
    while (current != null && !identical(current, ancestor)) {
      if (!current.attached) return null;
      if (current is RenderBox && !current.hasSize) return null;
      if (current is RenderSliver && current.geometry == null) return null;
      current = current.parent;
    }
    if (current == null) return null;
    final offset = box.localToGlobal(Offset.zero, ancestor: ancestor);
    return offset.isFinite ? offset : null;
  }

  @override
  bool updateShouldNotify(SlidingIndicatorScope oldWidget) =>
      !identical(hover, oldWidget.hover) ||
      !identical(selection, oldWidget.selection) ||
      contentOffsetOf != oldWidget.contentOffsetOf;
}

/// Fond animé d'une ligne, à placer dans sa surface entre le fond par défaut
/// et le contenu.
///
/// Peint la portion des indicateurs [hover] et [selection] de la
/// [SlidingIndicatorScope] englobante qui recouvre la ligne. Les widgets
/// d'indicateur couvrent toute la boîte de ligne (marges comprises) et sont
/// rognés aux bornes de l'underlay. Sans portée, rien n'est peint.
class SlidingIndicatorUnderlay extends StatelessWidget {
  /// Crée l'underlay d'une ligne.
  const SlidingIndicatorUnderlay({this.hover, this.selection, super.key});

  /// Apparence de l'indicateur de survol.
  final Widget? hover;

  /// Apparence de l'indicateur de sélection.
  final Widget? selection;

  @override
  Widget build(BuildContext context) {
    final scope = SlidingIndicatorScope.maybeOf(context);
    if (scope == null || (hover == null && selection == null)) {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hover != null)
          _IndicatorMirror(
            key: const ValueKey('hover'),
            motion: scope.hover,
            contentOffsetOf: scope.contentOffsetOf,
            child: hover,
          ),
        if (selection != null)
          _IndicatorMirror(
            key: const ValueKey('selection'),
            motion: scope.selection,
            contentOffsetOf: scope.contentOffsetOf,
            child: selection,
          ),
      ],
    );
  }
}

class _IndicatorMirror extends SingleChildRenderObjectWidget {
  const _IndicatorMirror({
    required this.motion,
    required this.contentOffsetOf,
    super.child,
    super.key,
  });

  final SlidingIndicatorMotion motion;
  final Offset? Function(RenderBox box) contentOffsetOf;

  @override
  _RenderIndicatorMirror createRenderObject(BuildContext context) =>
      _RenderIndicatorMirror(motion: motion, contentOffsetOf: contentOffsetOf);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderIndicatorMirror renderObject,
  ) {
    renderObject
      ..motion = motion
      ..contentOffsetOf = contentOffsetOf;
  }
}

/// Peint, rognée à sa taille, la portion de l'indicateur animé qui recouvre
/// cette boîte. L'enfant est mis en page à la taille de l'indicateur.
class _RenderIndicatorMirror extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderIndicatorMirror({
    required SlidingIndicatorMotion motion,
    required this._contentOffsetOf,
  }) : _motion = motion {
    _translucent = _isTranslucent(motion.opacity);
  }

  SlidingIndicatorMotion _motion;
  set motion(SlidingIndicatorMotion value) {
    if (identical(value, _motion)) return;
    if (attached) {
      _motion.removeListener(_handleMotion);
      value.addListener(_handleMotion);
    }
    _motion = value;
    _syncTranslucent();
    markNeedsLayout();
  }

  Offset? Function(RenderBox box) _contentOffsetOf;
  set contentOffsetOf(Offset? Function(RenderBox box) value) {
    if (value == _contentOffsetOf) return;
    _contentOffsetOf = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipRectLayer> _clipHandle = LayerHandle<ClipRectLayer>();
  final LayerHandle<OpacityLayer> _opacityHandle = LayerHandle<OpacityLayer>();
  Size _childLayoutSize = Size.zero;
  bool _translucent = false;
  bool _painted = false;

  static bool _isTranslucent(double opacity) {
    final alpha = Color.getAlphaFromOpacity(opacity);
    return alpha > 0 && alpha < 255;
  }

  static Size _sanitize(Size size) => Size(
    size.width.isFinite && size.width > 0 ? size.width : 0,
    size.height.isFinite && size.height > 0 ? size.height : 0,
  );

  void _syncTranslucent() {
    final translucent = _isTranslucent(_motion.opacity);
    if (translucent == _translucent) return;
    _translucent = translucent;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  bool _overlaps(Rect rect) {
    if (!hasSize || _motion.opacity <= 0) return false;
    final origin = _contentOffsetOf(this);
    if (origin == null) return true;
    return rect.shift(-origin).overlaps(Offset.zero & size);
  }

  void _handleMotion() {
    if (child == null) return;
    _syncTranslucent();
    final rect = _motion.rect;
    if (!hasSize || _sanitize(rect.size) != _childLayoutSize) {
      markNeedsLayout();
      return;
    }
    if (_painted || _overlaps(rect)) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _motion.addListener(_handleMotion);
  }

  @override
  void detach() {
    _motion.removeListener(_handleMotion);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _translucent;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => Size(
    constraints.hasBoundedWidth ? constraints.maxWidth : constraints.minWidth,
    constraints.hasBoundedHeight ? constraints.maxHeight : constraints.minHeight,
  );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) return;
    _childLayoutSize = _sanitize(_motion.rect.size);
    child.layout(BoxConstraints.tight(_childLayoutSize));
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  void _clearLayers() {
    _clipHandle.layer = null;
    _opacityHandle.layer = null;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _painted = false;
    final child = this.child;
    final origin = child == null ? null : _contentOffsetOf(this);
    final alpha = Color.getAlphaFromOpacity(_motion.opacity);
    if (child == null || origin == null || alpha == 0) {
      _clearLayers();
      return;
    }
    final local = _motion.rect.topLeft - origin;
    final bounds = Offset.zero & size;
    if (!(local & _childLayoutSize).overlaps(bounds)) {
      _clearLayers();
      return;
    }
    (child.parentData! as BoxParentData).offset = local;
    final translucent = alpha < 255 && needsCompositing;
    _clipHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      bounds,
      (context, offset) {
        if (translucent) {
          _opacityHandle.layer = context.pushOpacity(
            offset,
            alpha,
            (context, offset) => context.paintChild(child, offset + local),
            oldLayer: _opacityHandle.layer,
          );
        } else {
          _opacityHandle.layer = null;
          context.paintChild(child, offset + local);
        }
      },
      oldLayer: _clipHandle.layer,
    );
    _painted = true;
  }

  @override
  void dispose() {
    _clearLayers();
    super.dispose();
  }
}
