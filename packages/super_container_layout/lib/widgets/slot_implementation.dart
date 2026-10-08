import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'super_container.dart';

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

/// Empile les [slots] visibles d'une zone, de haut en bas.
class SlotStack extends StatelessWidget {
  const SlotStack({
    required this.slots,
    this.expand = true,
    this.stretch = true,
    this.showLabels = false,
    this.zoneLabel,
    this.mover,
    this.emphasis,
    this.preferredSizes = const {},
    this.onEditPreferredSize,
    super.key,
  });

  final List<SlotImplementation> slots;

  /// Les slots [SlotSizing.fill] se partagent la hauteur de la zone. Désactivé
  /// dans une zone de hauteur automatique, où tout slot a sa hauteur naturelle.
  final bool expand;

  /// Les slots prennent toute la largeur de la zone. Désactivé dans une zone de
  /// largeur automatique, où la largeur vient du slot le plus large.
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
  final Future<void> Function(SlotImplementation)? onEditPreferredSize;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final slot in slots)
        if (slot.visible) slot,
    ];
    final ids = [for (final slot in visible) slot.id];
    return _SlotColumn(
      expand: expand,
      stretch: stretch,
      preferredSizes: [
        for (final slot in visible)
          preferredSizes.containsKey(slot.id)
              ? preferredSizes[slot.id]
              : slot.preferredSize,
      ],
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
    enabled: showLabels && onEditPreferredSize != null,
    onEdit: () async => onEditPreferredSize?.call(slot),
    child: _LabeledSlot(
      slot: slot,
      showLabel: showLabels,
      mover: mover,
      emphasis: emphasis,
      zoneLabel: zoneLabel,
      ids: ids,
      caption: zoneLabel == null
          ? slot.label
          : '${slot.label} · $zoneLabel ${index + 1}/$count',
    ),
  );
}

class _SlotColumn extends MultiChildRenderObjectWidget {
  const _SlotColumn({
    required this.expand,
    required this.stretch,
    required this.preferredSizes,
    required this.sizing,
    required super.children,
  });

  final bool expand;
  final bool stretch;
  final List<Size?> preferredSizes;
  final List<SlotSizing> sizing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlotColumn()..configure(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSlotColumn renderObject,
  ) => renderObject.configure(this);
}

class _SlotParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSlotColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotParentData> {
  late _SlotColumn _configuration;

  void configure(_SlotColumn value) {
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
    final expand = _configuration.expand && constraints.hasBoundedHeight;
    final stretch = _configuration.stretch && constraints.hasBoundedWidth;
    var naturalHeight = 0.0;
    var preferredHeight = 0.0;
    var fills = 0;
    bool fillsSpace(int index) =>
        expand &&
        preferences[index] == null &&
        _configuration.sizing[index] == SlotSizing.fill;
    BoxConstraints childConstraints({Size? preferred, double? height}) {
      final width = preferred?.width.clamp(0.0, constraints.maxWidth);
      return BoxConstraints(
        minWidth: width ?? (stretch ? constraints.maxWidth : 0),
        maxWidth: width ?? constraints.maxWidth,
        minHeight: height ?? 0,
        maxHeight: height ?? constraints.maxHeight,
      );
    }

    // Mesurer le contenu naturel avant de partager le reste entre les tailles
    // preferees et les slots fill evite un debordement avec des slots mixtes.
    for (final (index, child) in children.indexed) {
      final preferred = preferences[index];
      if (preferred != null) {
        preferredHeight += preferred.height;
      } else if (fillsSpace(index)) {
        fills++;
      } else {
        child.layout(childConstraints(), parentUsesSize: true);
        naturalHeight += child.size.height;
      }
    }
    final available = (constraints.maxHeight - naturalHeight).clamp(
      0.0,
      double.infinity,
    );
    final scale = preferredHeight > available
        ? available / preferredHeight
        : 1.0;
    final fillHeight = fills == 0
        ? 0.0
        : (available - preferredHeight * scale).clamp(0.0, double.infinity) /
              fills;
    var height = 0.0;
    var width = 0.0;
    for (final (index, child) in children.indexed) {
      final preferred = preferences[index];
      if (preferred != null || fillsSpace(index)) {
        child.layout(
          childConstraints(
            preferred: preferred,
            height: preferred == null ? fillHeight : preferred.height * scale,
          ),
          parentUsesSize: true,
        );
      }
      (child.parentData! as _SlotParentData).offset = Offset(0, height);
      height += child.size.height;
      if (child.size.width > width) width = child.size.width;
    }
    size = constraints.constrain(
      Size(
        stretch ? constraints.maxWidth : width,
        expand ? constraints.maxHeight : height,
      ),
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
    required this.showLabel,
    required this.caption,
    required this.mover,
    required this.emphasis,
    required this.zoneLabel,
    required this.ids,
  });

  final SlotImplementation slot;
  final bool showLabel;
  final String caption;
  final SlotMover? mover;
  final LabelEmphasis? emphasis;
  final String? zoneLabel;

  /// Slots visibles de la zone, dans l'ordre.
  final List<String> ids;

  @override
  State<_LabeledSlot> createState() => _LabeledSlotState();
}

class _LabeledSlotState extends State<_LabeledSlot> {
  /// Vrai quand le glisser survole la moitié basse du slot.
  bool _after = false;

  /// L'étiquette est survolée ou glissée : le slot qu'elle désigne est surligné.
  bool _hover = false;
  bool _dragging = false;

  /// Cible annoncée par l'étiquette pendant qu'elle est glissée.
  final _hint = ValueNotifier<SlotDropHint?>(null);

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
    final after = box.globalToLocal(pointer).dy > box.size.height / 2;
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
    final canEditSize =
        widget.showLabel && ContainerMenuAction.of(context).isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
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
          if (accepts) details.data.hint.value = _hintFor(details.data);
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
            slot,
            if (_hover || _dragging)
              Positioned.fill(
                key: ValueKey('slot-highlight-${slot.id}'),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.tertiary.withValues(alpha: .12),
                      border: Border.all(color: colors.tertiary, width: 2),
                    ),
                  ),
                ),
              ),
            if (candidates.any((data) => data != null && data.id != slot.id))
              Positioned(
                key: ValueKey('slot-drop-position-${slot.id}'),
                left: 0,
                right: 0,
                top: _after ? null : 0,
                bottom: _after ? 0 : null,
                height: 3,
                child: IgnorePointer(
                  child: ColoredBox(
                    key: ValueKey('slot-drop-${slot.id}'),
                    color: colors.tertiary,
                  ),
                ),
              ),
            if (widget.showLabel && slot.showLabel)
              Positioned.fill(
                key: ValueKey('slot-label-position-${slot.id}'),
                child: Align(
                  alignment: slot.labelAlignment,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: EmphasizedLabel(
                      emphasis: widget.emphasis,
                      alignment: slot.labelAlignment,
                      child: MouseRegion(
                        hitTestBehavior: HitTestBehavior.translucent,
                        onEnter: (_) => _setHover(true),
                        onExit: (_) => _setHover(false),
                        child: mover == null
                            ? IgnorePointer(child: _chip(colors))
                            : Draggable<SlotDragData>(
                                data: SlotDragData(
                                  id: slot.id,
                                  owner: mover.owner,
                                  hint: _hint,
                                ),
                                dragAnchorStrategy: pointerDragAnchorStrategy,
                                hitTestBehavior: HitTestBehavior.translucent,
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
                                child: IgnorePointer(child: _chip(colors)),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
