import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart'
    show PointerDownEvent, kPrimaryButton, kTouchSlop;
import 'package:material_ui/material_ui.dart';

import '../../models/super_layout_config.dart';
import '../editing/editor_history.dart';
import '../editing/editor_overlay.dart';
import '../editing/editor_zoom.dart';
import '../editing/editor_dialog_header.dart';
import '../editing/editor_resize_handle.dart';
import '../surfaces/super_container.dart';

/// Taille qu'un slot demande à la zone qui le reçoit.
enum SlotSizing {
  /// Le slot remplit l'espace restant de sa zone.
  fill,

  /// Le slot prend la hauteur (ou la largeur) que demande son contenu.
  intrinsic,
}

/// Bloc majeur d'une page, rangé dans une zone d'un `SuperLayout` (le
/// récepteur de slots) grâce à son [id].
///
/// Une sous-classe décrit son contenu dans [buildSlot]. Un bloc avec état
/// l'enveloppe dans son propre `StatefulWidget` ; un bloc simple peut passer
/// par [BuilderSlot].
abstract class SlotImplementation extends StatelessWidget {
  const SlotImplementation({
    required this.id,
    required this.label,
    this.sizing = SlotSizing.fill,
    this.preferredSize,
    this.visible = true,
    this.showLabel = true,
    this.labelAlignment = Alignment.topLeft,
    super.key,
  });

  /// Identifiant stable, utilisé par `SuperLayoutConfig.placements`.
  final String id;
  final String label;
  final SlotSizing sizing;

  /// Dimensions demandees, limitees par l'espace disponible dans la zone.
  final Size? preferredSize;

  /// Un slot masqué n'est affiché dans aucune zone et n'occupe aucune place.
  final bool visible;

  /// Affiche le [label] du slot en mode édition.
  final bool showLabel;

  /// Coin du slot où se pose l'étiquette. Un slot qui contient une disposition
  /// la met d'un autre côté que celles de ses propres slots, qui commencent au
  /// même coin.
  final Alignment labelAlignment;

  @protected
  Widget buildSlot(BuildContext context);

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey('slot-$id'), child: buildSlot(context));
}

/// Slot dont le contenu est fourni par une fonction.
class BuilderSlot extends SlotImplementation {
  const BuilderSlot({
    required super.id,
    required super.label,
    required this.builder,
    super.sizing,
    super.preferredSize,
    super.visible,
    super.showLabel,
    super.labelAlignment,
    super.key,
  });

  final WidgetBuilder builder;

  @override
  Widget buildSlot(BuildContext context) => builder(context);
}

/// Preserves a component's state while exposing its instance name to editors.
class InstanceSlot extends SlotImplementation {
  InstanceSlot(
    this.component, {super.key, 
    required super.label,
    required this.onRename,
    required this.onRestore,
    required this.overridden,
  }) : super(
         id: component.id,
         sizing: component.sizing,
         preferredSize: component.preferredSize,
         visible: component.visible,
         showLabel: component.showLabel,
         labelAlignment: component.labelAlignment,
       );

  final SlotImplementation component;
  final ValueChanged<String> onRename;
  final VoidCallback onRestore;
  final bool overridden;

  @override
  Widget build(BuildContext context) => buildSlot(context);

  @override
  Widget buildSlot(BuildContext context) => EditorComponentLabel(
    label: label,
    onChanged: onRename,
    onRestore: onRestore,
    overridden: overridden,
    child: component,
  );
}

/// Aligne les [slots] visibles d'une zone selon [axis].
class SlotStack extends StatelessWidget {
  const SlotStack({
    required this.slots,
    this.axis = Axis.vertical,
    this.expand = true,
    this.stretch = true,
    this.showLabels = false,
    this.zoneLabel,
    this.mover,
    this.emphasis,
    this.preferredSizes = const {},
    this.sizeConstraints = const {},
    this.layoutSize = Size.zero,
    this.onEditPreferredSize,
    this.onRemoveSlot,
    this.onSelectSlot,
    this.onTapSlot,
    this.selectedSlotId,
    this.onResizeSlot,
    this.focusKeys,
    super.key,
  });

  final List<SlotImplementation> slots;
  final Map<String, GlobalKey>? focusKeys;
  final Axis axis;

  /// Les slots [SlotSizing.fill] se partagent l'espace sur l'axe principal.
  /// Desactive dans une zone automatique sur cet axe.
  final bool expand;

  /// Les slots occupent tout l'axe transversal, sauf taille preferee.
  /// Desactive dans une zone automatique sur cet axe.
  final bool stretch;

  /// Pose le [SlotImplementation.label] de chaque slot sur son rectangle. Le
  /// slot garde la même place dans l'arbre, donc son état, que l'étiquette
  /// soit affichée ou non.
  final bool showLabels;

  /// Nom de la zone qui reçoit les slots, ajouté à leur étiquette avec leur
  /// position dans la zone.
  final String? zoneLabel;

  /// Rend les étiquettes déplaçables : glissées sur un autre slot du même
  /// propriétaire, elles se rangent avant ou après lui.
  final SlotMover? mover;

  /// Grossissement partagé des étiquettes (zones et slots) de la disposition.
  final LabelEmphasis? emphasis;
  final Map<String, Size?> preferredSizes;
  final Map<String, SlotSizeConstraints> sizeConstraints;
  final Size layoutSize;
  final Future<void> Function(SlotImplementation)? onEditPreferredSize;
  final Future<void> Function(SlotImplementation)? onRemoveSlot;
  final ValueChanged<SlotImplementation>? onSelectSlot;

  /// Content clicks, distinct from the label's selection toggle.
  final void Function(SlotImplementation, PointerDownEvent)? onTapSlot;
  final String? selectedSlotId;
  final void Function(SlotImplementation, SlotSizeConstraints)? onResizeSlot;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final slot in slots)
        if (slot.visible) slot,
    ];
    final ids = [for (final slot in visible) slot.id];
    return _SlotFlex(
      axis: axis,
      expand: expand,
      stretch: stretch,
      preferredSizes: [
        for (final slot in visible)
          sizeConstraints.containsKey(slot.id)
              ? null
              : preferredSizes.containsKey(slot.id)
              ? preferredSizes[slot.id]
              : slot.preferredSize,
      ],
      sizeConstraints: [for (final slot in visible) sizeConstraints[slot.id]],
      layoutSize: layoutSize,
      sizing: [for (final slot in visible) slot.sizing],
      children: [
        for (final (index, slot) in visible.indexed)
          _labeled(slot, index, visible.length, ids),
      ],
    );
  }

  Widget _labeled(
    SlotImplementation slot,
    int index,
    int count,
    List<String> ids,
  ) => ContainerMenuAction(
    key: ValueKey('slot-item-${slot.id}'),
    label: 'Taille préférée : ${slot.label}',
    inline: true,
    enabled: onEditPreferredSize != null,
    onEdit: () async => onEditPreferredSize?.call(slot),
    onRemove: onRemoveSlot != null
        ? () async => onRemoveSlot?.call(slot)
        : null,
    child: KeyedSubtree(
      key: focusKeys?.putIfAbsent(slot.id, GlobalKey.new),
      child: _LabeledSlot(
        slot: slot,
        axis: axis,
        showLabel: showLabels,
        mover: mover,
        emphasis: emphasis,
        zoneLabel: zoneLabel,
        ids: ids,
        onSelect: onSelectSlot == null ? null : () => onSelectSlot!(slot),
        onTapContent: onTapSlot == null
            ? null
            : (event) => onTapSlot!(slot, event),
        selected: selectedSlotId == slot.id,
        onResize: onResizeSlot == null
            ? null
            : (dimensions) => onResizeSlot!(slot, dimensions),
        sizeConstraints: sizeConstraints[slot.id],
        caption: zoneLabel == null
            ? slot.label
            : '${slot.label} · $zoneLabel ${index + 1}/$count',
      ),
    ),
  );
}

class _SlotFlex extends MultiChildRenderObjectWidget {
  const _SlotFlex({
    required this.axis,
    required this.expand,
    required this.stretch,
    required this.preferredSizes,
    required this.sizeConstraints,
    required this.layoutSize,
    required this.sizing,
    required super.children,
  });

  final bool expand;
  final Axis axis;
  final bool stretch;
  final List<Size?> preferredSizes;
  final List<SlotSizeConstraints?> sizeConstraints;
  final Size layoutSize;
  final List<SlotSizing> sizing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlotFlex()..configure(this);

  @override
  void updateRenderObject(BuildContext context, _RenderSlotFlex renderObject) =>
      renderObject.configure(this);
}

class _SlotParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSlotFlex extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotParentData> {
  late _SlotFlex _configuration;
  List<(double, double, double?, double, double, double?)> _bounds = const [];

  ({Size min, Size max}) resizeBounds(int index) {
    final horizontal = _configuration.axis == Axis.horizontal;
    final bound = _bounds[index];
    final available = constraints.biggest;
    var maxMain = horizontal ? available.width : available.height;
    final children = getChildrenAsList();
    for (final (other, child) in children.indexed) {
      if (other == index) continue;
      final flexible =
          _configuration.expand &&
          _bounds[other].$3 == null &&
          _configuration.sizing[other] == SlotSizing.fill;
      maxMain -= flexible
          ? _bounds[other].$1
          : _bounds[other].$3 != null
          ? _bounds[other].$3!.clamp(_bounds[other].$1, _bounds[other].$2)
          : horizontal
          ? child.size.width
          : child.size.height;
    }
    if (bound.$2 < maxMain) maxMain = bound.$2;
    return (
      min: horizontal ? Size(bound.$1, bound.$4) : Size(bound.$4, bound.$1),
      max: horizontal ? Size(maxMain, bound.$5) : Size(bound.$5, maxMain),
    );
  }

  Size get resizeBasis => Size(
    constraints.maxWidth.isFinite ? constraints.maxWidth : size.width,
    constraints.maxHeight.isFinite ? constraints.maxHeight : size.height,
  );

  void configure(_SlotFlex value) {
    _configuration = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotParentData) {
      child.parentData = _SlotParentData();
    }
  }

  @override
  void performLayout() {
    final children = getChildrenAsList();
    final preferences = _configuration.preferredSizes;
    final sizeConstraints = _configuration.sizeConstraints;
    final horizontal = _configuration.axis == Axis.horizontal;
    double mainExtent(Size size) => horizontal ? size.width : size.height;
    double crossExtent(Size size) => horizontal ? size.height : size.width;
    Size dimensions(double main, double cross) =>
        horizontal ? Size(main, cross) : Size(cross, main);
    final maxMain = mainExtent(constraints.biggest);
    final maxCross = crossExtent(constraints.biggest);
    final layoutMain = mainExtent(_configuration.layoutSize);
    final layoutCross = crossExtent(_configuration.layoutSize);
    final expand = _configuration.expand && maxMain.isFinite;
    final stretch = _configuration.stretch && maxCross.isFinite;
    final bounds = <(double, double, double?, double, double, double?)>[];
    for (final (index, _) in children.indexed) {
      final legacy = preferences[index];
      final configured = sizeConstraints[index];
      double? value(
        SlotDimension? dimension,
        double available,
        double wholeLayout,
      ) => dimension?.resolve(
        configured?.percentBasis == SlotPercentBasis.layout
            ? wholeLayout
            : available,
      );
      double? preferredMain = configured == null
          ? legacy == null
                ? null
                : mainExtent(legacy)
          : value(
              horizontal
                  ? configured.preferredWidth
                  : configured.preferredHeight,
              maxMain,
              layoutMain,
            );
      double? preferredCross = configured == null
          ? legacy == null
                ? null
                : crossExtent(legacy)
          : value(
              horizontal
                  ? configured.preferredHeight
                  : configured.preferredWidth,
              maxCross,
              layoutCross,
            );
      double bound(
        SlotDimension? dimension,
        double available,
        double wholeLayout,
        double fallback,
      ) => (value(dimension, available, wholeLayout) ?? fallback).clamp(
        0.0,
        available.isFinite ? available : double.infinity,
      );
      final minMain = bound(
        configured == null
            ? null
            : horizontal
            ? configured.minWidth
            : configured.minHeight,
        maxMain,
        layoutMain,
        0,
      );
      final maxConfiguredMain = bound(
        configured == null
            ? null
            : horizontal
            ? configured.maxWidth
            : configured.maxHeight,
        maxMain,
        layoutMain,
        maxMain,
      );
      final minCross = bound(
        configured == null
            ? null
            : horizontal
            ? configured.minHeight
            : configured.minWidth,
        maxCross,
        layoutCross,
        0,
      );
      final maxConfiguredCross = bound(
        configured == null
            ? null
            : horizontal
            ? configured.maxHeight
            : configured.maxWidth,
        maxCross,
        layoutCross,
        maxCross,
      );
      final effectiveMaxMain = maxConfiguredMain < minMain
          ? minMain
          : maxConfiguredMain;
      final effectiveMaxCross = maxConfiguredCross < minCross
          ? minCross
          : maxConfiguredCross;
      if (preferredMain != null) {
        final hasConfiguredMax =
            configured != null &&
            (horizontal
                ? configured.maxWidth != null
                : configured.maxHeight != null);
        preferredMain = preferredMain.clamp(
          minMain,
          hasConfiguredMax ? effectiveMaxMain : double.infinity,
        );
      }
      if (preferredCross != null) {
        preferredCross = preferredCross.clamp(minCross, effectiveMaxCross);
      }
      bounds.add((
        minMain,
        effectiveMaxMain,
        preferredMain,
        minCross,
        effectiveMaxCross,
        preferredCross,
      ));
    }
    _bounds = bounds;
    var naturalExtent = 0.0;
    var preferredExtent = 0.0;
    var fills = 0;
    bool fillsSpace(int index) =>
        expand &&
        bounds[index].$3 == null &&
        _configuration.sizing[index] == SlotSizing.fill;
    BoxConstraints childConstraints(int index, {double? main, double? cross}) {
      final bound = bounds[index];
      final min = dimensions(
        main ?? bound.$1,
        cross ?? (stretch ? bound.$5 : bound.$4),
      );
      final max = dimensions(main ?? bound.$2, cross ?? bound.$5);
      return BoxConstraints(
        minWidth: min.width,
        maxWidth: max.width,
        minHeight: min.height,
        maxHeight: max.height,
      );
    }

    // Mesurer le contenu naturel avant de partager le reste entre les tailles
    // preferees et les slots fill evite un debordement avec des slots mixtes.
    for (final (index, child) in children.indexed) {
      final bound = bounds[index];
      if (bound.$3 != null) {
        preferredExtent += bound.$3!;
      } else if (fillsSpace(index)) {
        fills++;
      } else {
        child.layout(
          childConstraints(index, cross: bound.$6),
          parentUsesSize: true,
        );
        naturalExtent += mainExtent(child.size);
      }
    }
    final available = (maxMain - naturalExtent).clamp(0.0, double.infinity);
    final scale = preferredExtent > available
        ? available / preferredExtent
        : 1.0;
    final fillExtent = fills == 0
        ? 0.0
        : (available - preferredExtent * scale).clamp(0.0, double.infinity) /
              fills;
    var main = 0.0;
    var cross = 0.0;
    for (final (index, child) in children.indexed) {
      final bound = bounds[index];
      if (bound.$3 != null || fillsSpace(index)) {
        final desiredMain = bound.$3 ?? fillExtent.clamp(bound.$1, bound.$2);
        final scaledMain = bound.$3 == null
            ? desiredMain
            : (desiredMain * scale).clamp(bound.$1, bound.$2);
        child.layout(
          childConstraints(index, main: scaledMain, cross: bound.$6),
          parentUsesSize: true,
        );
      }
      (child.parentData! as _SlotParentData).offset = horizontal
          ? Offset(main, 0)
          : Offset(0, main);
      main += mainExtent(child.size);
      if (crossExtent(child.size) > cross) cross = crossExtent(child.size);
    }
    size = constraints.constrain(
      dimensions(expand ? maxMain : main, stretch ? maxCross : cross),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Données d'un glisser de slot.
class SlotDragData {
  const SlotDragData({
    required this.id,
    required this.owner,
    required this.hint,
  });

  final String id;

  /// Récepteur des slots (un `SuperLayout`) : seul lui accepte le dépôt.
  final Object owner;

  /// Où le slot atterrirait s'il était lâché ici ; la cible survolée le met à
  /// jour, l'étiquette glissée l'affiche.
  final ValueNotifier<SlotDropHint?> hint;
}

/// Zone et rang qu'aurait un slot déposé sur la cible survolée.
class SlotDropHint {
  const SlotDropHint({
    required this.zoneLabel,
    required this.position,
    required this.total,
  });

  final String zoneLabel;
  final int position;
  final int total;

  String get caption => '$zoneLabel $position/$total';

  /// Rang d'un slot placé après [before] slots parmi les [others] autres.
  static SlotDropHint? at({
    required String? zoneLabel,
    required List<String> ids,
    required String movedId,
    String? beforeId,
    String? afterId,
  }) {
    if (zoneLabel == null) return null;
    final others = [
      for (final id in ids)
        if (id != movedId) id,
    ];
    var at = others.length;
    if (beforeId != null) {
      final index = others.indexOf(beforeId);
      if (index >= 0) at = index;
    } else if (afterId != null) {
      final index = others.indexOf(afterId);
      if (index >= 0) at = index + 1;
    }
    return SlotDropHint(
      zoneLabel: zoneLabel,
      position: at + 1,
      total: others.length + 1,
    );
  }
}

/// Mise en avant des étiquettes d'une disposition. Une étiquette survolée ou
/// glissée signale sa zone (la portée) : les étiquettes de slot de cette zone
/// grossissent, et les noms de toutes les zones.
class LabelEmphasis {
  const LabelEmphasis({
    required this.scopes,
    required this.scope,
    required this.onHover,
  });

  /// Zones dont une étiquette est survolée ou glissée.
  final ValueListenable<Set<Object>> scopes;

  /// Zone de l'étiquette qui utilise cet objet.
  final Object scope;

  /// L'étiquette [source] de la zone [scope] est survolée ou lâchée.
  final void Function(Object scope, Object source, bool hovered) onHover;

  /// Signale le survol (ou la fin du survol) de l'étiquette [source].
  void report(Object source, bool hovered) => onHover(scope, source, hovered);
}

/// Agrandit son enfant quand une étiquette est survolée ; sans effet de mise
/// en page : l'enfant garde sa place.
class EmphasizedLabel extends StatelessWidget {
  const EmphasizedLabel({
    required this.emphasis,
    required this.child,
    this.alignment = Alignment.center,
    this.allScopes = false,
    super.key,
  });

  static const scale = 1.3;

  final LabelEmphasis? emphasis;
  final Alignment alignment;

  /// Grossit dès qu'une étiquette de la disposition est survolée, quelle que
  /// soit sa zone ; sinon seulement pour une étiquette de la même zone.
  final bool allScopes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final emphasis = this.emphasis;
    if (emphasis == null) return child;
    return ValueListenableBuilder<Set<Object>>(
      valueListenable: emphasis.scopes,
      child: child,
      builder: (context, scopes, child) => AnimatedScale(
        scale: (allScopes ? scopes.isNotEmpty : scopes.contains(emphasis.scope))
            ? scale
            : 1,
        alignment: alignment,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// Déplacement des slots d'une zone vers un autre rang.
class SlotMover {
  const SlotMover({required this.owner, required this.onMove});

  final Object owner;

  /// Range [id] juste avant [beforeId] ou juste après [afterId].
  final void Function(String id, {String? beforeId, String? afterId}) onMove;
}

/// Un slot, son étiquette d'édition et sa cible de dépôt. Le slot reste le
/// premier enfant du `Stack` : son état survit au mode édition.
class _LabeledSlot extends StatefulWidget {
  const _LabeledSlot({
    required this.slot,
    required this.axis,
    required this.showLabel,
    required this.caption,
    required this.mover,
    required this.emphasis,
    required this.zoneLabel,
    required this.ids,
    required this.onSelect,
    required this.onTapContent,
    required this.selected,
    required this.onResize,
    required this.sizeConstraints,
  });

  final SlotImplementation slot;
  final Axis axis;
  final bool showLabel;
  final String caption;
  final SlotMover? mover;
  final LabelEmphasis? emphasis;
  final String? zoneLabel;
  final VoidCallback? onSelect;
  final ValueChanged<PointerDownEvent>? onTapContent;
  final bool selected;
  final ValueChanged<SlotSizeConstraints>? onResize;
  final SlotSizeConstraints? sizeConstraints;

  /// Slots visibles de la zone, dans l'ordre.
  final List<String> ids;

  @override
  State<_LabeledSlot> createState() => _LabeledSlotState();
}

class _LabeledSlotState extends State<_LabeledSlot> {
  int? _tapPointer;
  Offset? _tapStart;
  VoidCallback? _tapAction;
  final _labelKey = GlobalKey();

  /// Vrai quand le glisser survole la seconde moitie sur l'axe du slot.
  bool _after = false;

  /// L'étiquette est survolée ou glissée : le slot qu'elle désigne est surligné.
  bool _hover = false;
  bool _dragging = false;

  /// Cible annoncée par l'étiquette pendant qu'elle est glissée.
  final _hint = ValueNotifier<SlotDropHint?>(null);
  final _resizeOverlay = OverlayPortalController();
  _RenderSlotFlex? _resizeLayout;
  Offset? _resizeStart;
  Size _resizeSize = Size.zero;
  SlotSizeConstraints? _resizeConstraints;
  Size? _resizeLegacySize;
  EditorHistoryController? _resizeHistory;
  bool _resizeBlocked = false;

  bool get _showResizeHandles =>
      widget.showLabel && widget.selected && widget.onResize != null;

  void _syncResizeOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showResizeHandles) {
        _resizeOverlay.show();
      } else {
        _resizeOverlay.hide();
        _finishResize();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _syncResizeOverlay();
  }

  @override
  void didUpdateWidget(_LabeledSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncResizeOverlay();
  }

  void _beginResize(DragStartDetails details) {
    final layout = context.findAncestorRenderObjectOfType<_RenderSlotFlex>()!;
    final box = context.findRenderObject()! as RenderBox;
    _resizeLayout = layout;
    _resizeStart = layout.globalToLocal(details.globalPosition);
    _resizeSize = box.size;
    _resizeConstraints = widget.sizeConstraints;
    _resizeLegacySize = layout
        ._configuration
        .preferredSizes[widget.ids.indexOf(widget.slot.id)];
    _resizeBlocked = false;
    _resizeHistory = EditorHistoryScope.controllerOf(context);
    _resizeHistory?.beginTransaction();
    setState(() {});
  }

  void _resize(DragUpdateDetails details, Alignment corner) {
    final layout = _resizeLayout;
    final start = _resizeStart;
    if (layout == null || start == null || !layout.attached) return;
    final bounds = layout.resizeBounds(widget.ids.indexOf(widget.slot.id));
    final saved = _resizeConstraints;
    final legacySize = _resizeLegacySize;
    final basis = saved?.percentBasis == SlotPercentBasis.layout
        ? layout._configuration.layoutSize
        : layout.resizeBasis;
    final minWidth = saved?.minWidth?.resolve(basis.width) ?? 0;
    final minHeight = saved?.minHeight?.resolve(basis.height) ?? 0;
    final maxWidth = saved?.maxWidth?.resolve(basis.width) ?? bounds.max.width;
    final maxHeight =
        saved?.maxHeight?.resolve(basis.height) ?? bounds.max.height;
    final lowerWidth = bounds.min.width > 1 ? bounds.min.width : 1.0;
    final lowerHeight = bounds.min.height > 1 ? bounds.min.height : 1.0;
    if (bounds.max.width < lowerWidth ||
        bounds.max.height < lowerHeight ||
        minWidth > bounds.max.width ||
        minHeight > bounds.max.height ||
        maxWidth < minWidth ||
        maxHeight < minHeight) {
      if (!_resizeBlocked) {
        _resizeBlocked = true;
        final message =
            'Redimensionnement de ${widget.slot.label} impossible : '
            'les bornes min/max sont incompatibles avec l’espace disponible.';
        debugPrint(message);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    final delta = layout.globalToLocal(details.globalPosition) - start;
    final width = (_resizeSize.width + delta.dx * corner.x).clamp(
      lowerWidth,
      bounds.max.width,
    );
    final height = (_resizeSize.height + delta.dy * corner.y).clamp(
      lowerHeight,
      bounds.max.height,
    );
    SlotDimension dimension(
      double value,
      SlotDimension? original,
      double base,
    ) => original?.unit == SlotSizeUnit.percent && base > 0 && base.isFinite
        ? SlotDimension(value * 100 / base, SlotSizeUnit.percent)
        : SlotDimension(value, SlotSizeUnit.pixels);
    widget.onResize?.call(
      SlotSizeConstraints(
        minWidth: saved?.minWidth,
        minHeight: saved?.minHeight,
        maxWidth: saved?.maxWidth,
        maxHeight: saved?.maxHeight,
        preferredWidth: corner.x == 0
            ? saved?.preferredWidth ??
                  (saved == null && legacySize != null
                      ? SlotDimension(legacySize.width, SlotSizeUnit.pixels)
                      : null)
            : dimension(width, saved?.preferredWidth, basis.width),
        preferredHeight: corner.y == 0
            ? saved?.preferredHeight ??
                  (saved == null && legacySize != null
                      ? SlotDimension(legacySize.height, SlotSizeUnit.pixels)
                      : null)
            : dimension(height, saved?.preferredHeight, basis.height),
        percentBasis: saved?.percentBasis ?? SlotPercentBasis.zone,
      ),
    );
  }

  void _finishResize() {
    final wasResizing = _resizeStart != null;
    _resizeLayout = null;
    _resizeStart = null;
    _resizeHistory?.commitTransaction();
    _resizeHistory = null;
    if (wasResizing && mounted) setState(() {});
  }

  Widget _resizeHandle(String name, Alignment corner, ColorScheme colors) =>
      EditorResizeHandle(
        key: ValueKey('slot-resize-${widget.slot.id}-$name'),
        direction: corner,
        label: widget.slot.label,
        onStart: _beginResize,
        onUpdate: (details) => _resize(details, corner),
        onEnd: _finishResize,
      );

  void _setHover(bool value) {
    if (mounted && value != _hover) {
      setState(() => _hover = value);
      _reportEmphasis();
    }
  }

  void _setDragging(bool value) {
    if (!value) _hint.value = null;
    if (mounted && value != _dragging) {
      setState(() => _dragging = value);
      _reportEmphasis();
    }
  }

  void _reportEmphasis() =>
      widget.emphasis?.report(widget.slot.id, _hover || _dragging);

  @override
  void dispose() {
    _finishResize();
    final emphasis = widget.emphasis;
    if (emphasis != null && (_hover || _dragging)) {
      // Le parent ne doit pas être notifié pendant le démontage.
      final id = widget.slot.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => emphasis.report(id, false),
      );
    }
    super.dispose();
  }

  /// Rang du slot glissé s'il était lâché avant ou après ce slot.
  SlotDropHint? _hintFor(SlotDragData data) => data.id == widget.slot.id
      ? null
      : SlotDropHint.at(
          zoneLabel: widget.zoneLabel,
          ids: widget.ids,
          movedId: data.id,
          beforeId: _after ? null : widget.slot.id,
          afterId: _after ? widget.slot.id : null,
        );
  bool _accepts(SlotDragData data) =>
      widget.mover != null && identical(data.owner, widget.mover!.owner);

  void _track(Offset pointer) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(pointer);
    final after = widget.axis == Axis.horizontal
        ? local.dx > box.size.width / 2
        : local.dy > box.size.height / 2;
    if (after != _after) setState(() => _after = after);
  }

  Widget _chip(
    ColorScheme colors, {
    double opacity = .85,
    bool dragged = false,
  }) => Material(
    key: ValueKey('slot-label-${widget.slot.id}'),
    color: colors.tertiary.withValues(alpha: opacity),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: dragged
          ? ValueListenableBuilder<SlotDropHint?>(
              valueListenable: _hint,
              builder: (context, hint, _) => Text(
                hint == null
                    ? widget.caption
                    : '${widget.slot.label} → ${hint.caption}',
                style: TextStyle(fontSize: 11, color: colors.onTertiary),
              ),
            )
          : Text(
              widget.caption,
              style: TextStyle(fontSize: 11, color: colors.onTertiary),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slot = widget.slot;
    final mover = widget.mover;
    final canEditSize = ContainerMenuAction.of(context).isNotEmpty;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _resizeOverlay,
      overlayChildBuilder: (context, info) {
        final handles = Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (name, corner) in editorResizeDirections)
              Positioned.fill(
                child: Align(
                  alignment: corner,
                  child: _resizeHandle(name, corner, colors),
                ),
              ),
            if (_resizeStart != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 34),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            '${info.childSize.width.round()} × ${info.childSize.height.round()} px',
                            key: ValueKey('slot-resize-size-${slot.id}'),
                            style: TextStyle(
                              color: colors.onTertiaryContainer,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        if (EditorZoomScope.contains(context)) {
          return Positioned.fromRect(
            rect: MatrixUtils.transformRect(
              info.childPaintTransform,
              Offset.zero & info.childSize,
            ),
            child: handles,
          );
        }
        return Positioned(
          left: 0,
          top: 0,
          child: Transform(
            transform: info.childPaintTransform,
            child: SizedBox.fromSize(size: info.childSize, child: handles),
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onSecondaryTapUp: canEditSize
            ? (details) => context
                  .findAncestorStateOfType<SuperContainerState>()
                  ?.openMenu(
                    details.globalPosition,
                    actions: ContainerMenuAction.of(context),
                  )
            : null,
        child: DragTarget<SlotDragData>(
          // Déposer un slot sur lui-même est accepté sans effet : la zone qui le
          // contient ne doit pas le ranger en dernier.
          onWillAcceptWithDetails: (details) {
            final accepts = _accepts(details.data);
            if (accepts) {
              _track(details.offset);
              details.data.hint.value = _hintFor(details.data);
            }
            return accepts;
          },
          onMove: (details) {
            _track(details.offset);
            details.data.hint.value = _hintFor(details.data);
          },
          onLeave: (data) => data?.hint.value = null,
          onAcceptWithDetails: (details) {
            if (details.data.id == slot.id) return;
            mover!.onMove(
              details.data.id,
              beforeId: _after ? null : slot.id,
              afterId: _after ? slot.id : null,
            );
          },
          builder: (context, candidates, _) => Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  // Portal labels can hit-test alongside the content below.
                  final label = _labelKey.currentContext?.findRenderObject();
                  final onLabel =
                      label is RenderBox &&
                      label.hasSize &&
                      (Offset.zero & label.size).contains(
                        label.globalToLocal(event.position),
                      );
                  if (event.buttons != kPrimaryButton ||
                      onLabel ||
                      _tapPointer != null) {
                    _tapAction = null;
                    return;
                  }
                  _tapPointer = event.pointer;
                  _tapStart = event.position;
                  final callback = widget.onTapContent;
                  _tapAction = callback == null ? null : () => callback(event);
                },
                onPointerMove: (event) {
                  if (event.pointer == _tapPointer &&
                      (event.position - _tapStart!).distance > kTouchSlop) {
                    _tapAction = null;
                  }
                },
                onPointerCancel: (event) {
                  if (event.pointer == _tapPointer) {
                    _tapPointer = null;
                    _tapStart = null;
                    _tapAction = null;
                  }
                },
                onPointerUp: (event) {
                  if (event.pointer != _tapPointer) return;
                  final action =
                      (event.position - _tapStart!).distance <= kTouchSlop
                      ? _tapAction
                      : null;
                  _tapPointer = null;
                  _tapStart = null;
                  _tapAction = null;
                  action?.call();
                },
                child: slot,
              ),
              if (_hover || _dragging || (widget.showLabel && widget.selected))
                Positioned.fill(
                  key: ValueKey('slot-highlight-${slot.id}'),
                  child: EditorOverlay(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.tertiary.withValues(alpha: .12),
                          border: Border.all(color: colors.tertiary, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              if (candidates.any((data) => data != null && data.id != slot.id))
                Positioned.fill(
                  child: EditorOverlay(
                    child: Align(
                      alignment: widget.axis == Axis.horizontal
                          ? (_after
                                ? Alignment.centerRight
                                : Alignment.centerLeft)
                          : (_after
                                ? Alignment.bottomCenter
                                : Alignment.topCenter),
                      child: SizedBox(
                        key: ValueKey('slot-drop-position-${slot.id}'),
                        width: widget.axis == Axis.horizontal
                            ? 3
                            : double.infinity,
                        height: widget.axis == Axis.vertical
                            ? 3
                            : double.infinity,
                        child: IgnorePointer(
                          child: ColoredBox(
                            key: ValueKey('slot-drop-${slot.id}'),
                            color: colors.tertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.showLabel && slot.showLabel)
                Positioned.fill(
                  key: ValueKey('slot-label-position-${slot.id}'),
                  child: EditorOverlay(
                    child: Align(
                      alignment: slot.labelAlignment,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: EmphasizedLabel(
                          emphasis: widget.emphasis,
                          alignment: slot.labelAlignment,
                          child: MouseRegion(
                            key: _labelKey,
                            hitTestBehavior: HitTestBehavior.translucent,
                            onEnter: (_) => _setHover(true),
                            onExit: (_) => _setHover(false),
                            child: GestureDetector(
                              key: ValueKey('slot-label-select-${slot.id}'),
                              onTap: widget.onSelect,
                              behavior: HitTestBehavior.translucent,
                              child: mover == null
                                  ? IgnorePointer(child: _chip(colors))
                                  : Draggable<SlotDragData>(
                                      data: SlotDragData(
                                        id: slot.id,
                                        owner: mover.owner,
                                        hint: _hint,
                                      ),
                                      dragAnchorStrategy:
                                          pointerDragAnchorStrategy,
                                      hitTestBehavior:
                                          HitTestBehavior.translucent,
                                      onDragStarted: () => _setDragging(true),
                                      onDragEnd: (_) => _setDragging(false),
                                      feedback: _chip(
                                        colors,
                                        opacity: 1,
                                        dragged: true,
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: .35,
                                        child: _chip(colors),
                                      ),
                                      // Le contenu sous l'étiquette reste atteignable (clic
                                      // droit du style) : seul le Draggable écoute le glisser.
                                      child: IgnorePointer(
                                        child: _chip(colors),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
