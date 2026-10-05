import 'package:flutter/foundation.dart'
    show ValueListenable, listEquals, setEquals;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../models/super_layout_config.dart';
import '../super_app.dart';
import 'layout_selection.dart';
import 'slot_implementation.dart';
import 'super_container.dart';

/// Disposition en neuf zones (Nord, Sud, Est, Ouest, coins et Centre) dont la
/// structure s'édite par clic droit, comme un [SuperContainer].
///
/// Les zones sont les récepteurs de [slots] : chaque [SlotImplementation] est
/// rangé dans une zone par [SuperLayoutConfig.placements] (ids ordonnés, empilés
/// de haut en bas). Une zone sans slot visible montre un repère portant son
/// nom. Le widget occupe tout l'espace disponible.
///
/// Un côté en taille automatique ([SuperLayoutConfig.autoSides]) prend la
/// taille de son contenu ; le centre reçoit le reste.
class SuperLayout extends StatefulWidget {
  const SuperLayout({
    this.slots = const [],
    this.config = const SuperLayoutConfig(),
    this.onChanged,
    this.label = 'Super layout',
    this.name,
    this.editable = true,
    this.showZoneNames = true,
    super.key,
  });

  final List<SlotImplementation> slots;
  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig>? onChanged;
  final String label;

  /// Nom court de la disposition, affiché dans le chemin de la bannière du mode
  /// édition ; [label] par défaut.
  final String? name;
  final bool editable;

  /// Affiche le nom des zones pendant le mode édition ; à désactiver pour une
  /// disposition imbriquée qui ne s'édite pas.
  final bool showZoneNames;

  @override
  State<SuperLayout> createState() => SuperLayoutState();
}

class SuperLayoutState extends State<SuperLayout> {
  late final ValueNotifier<SuperLayoutConfig> _config = ValueNotifier(
    widget.config,
  );

  SuperLayoutConfig get config => _config.value;

  /// Vrai quand un nom de zone glissé survole le centre.
  final _overCenter = ValueNotifier(false);

  /// Vrai quand le nom d'une autre zone est survolé ou glissé : le centre, qui
  /// reçoit l'échange, est surligné.
  final _centerHint = ValueNotifier(false);
  final _hinting = <SuperLayoutZone>{};

  /// Zone sélectionnée par un clic sur son nom : seule elle montre les
  /// étiquettes des dispositions imbriquées dans ses slots.
  final _selected = ValueNotifier<SuperLayoutZone?>(null);

  void _select(SuperLayoutZone zone) =>
      _selected.value = _selected.value == zone ? null : zone;

  List<String> _reportedPath = const [];

  /// Déclare le chemin des zones sélectionnées à la bannière du mode édition.
  void _reportPath(List<String> path) {
    if (listEquals(_reportedPath, path)) return;
    _reportedPath = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && listEquals(_reportedPath, path)) {
        LayoutSelection.report(this, path, clear: () => _selected.value = null);
      }
    });
  }

  /// Zones dont une étiquette (nom de zone ou slot) est survolée ou glissée :
  /// leurs étiquettes de slot et tous les noms de zone grossissent.
  final _emphasis = ValueNotifier<Set<Object>>(const {});
  final _emphasizing = <Object, Set<Object>>{};

  LabelEmphasis _emphasisFor(SuperLayoutZone zone) =>
      LabelEmphasis(scopes: _emphasis, scope: zone, onHover: _emphasize);

  void _emphasize(Object scope, Object source, bool hovered) {
    if (!mounted) return;
    final sources = _emphasizing[scope] ?? <Object>{};
    if (!(hovered ? sources.add(source) : sources.remove(source))) return;
    if (sources.isEmpty) {
      _emphasizing.remove(scope);
    } else {
      _emphasizing[scope] = sources;
    }
    _emphasis.value = {..._emphasizing.keys};
  }

  void _hintCenter(SuperLayoutZone zone, bool active) {
    if (!mounted) return;
    if (active ? _hinting.add(zone) : _hinting.remove(zone)) {
      _centerHint.value = _hinting.isNotEmpty;
    }
  }

  @override
  void didUpdateWidget(SuperLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) _config.value = widget.config;
  }

  @override
  void dispose() {
    _config.dispose();
    _overCenter.dispose();
    _centerHint.dispose();
    _emphasis.dispose();
    _selected.dispose();
    final owner = this;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => LayoutSelection.report(owner, const []),
    );
    super.dispose();
  }

  void _update(SuperLayoutConfig value) {
    if (value == _config.value) return;
    _config.value = value;
    widget.onChanged?.call(value);
  }

  Future<void> _openEditor() async {
    final initial = _config.value;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (context) => AlertDialog(
        title: Text(widget.label),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: _config,
              builder: (context, _) =>
                  SuperLayoutEditor(config: _config.value, onChanged: _update),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
    if (confirmed != true && mounted) _update(initial);
  }

  Future<void> _addSlot(SuperLayoutZone zone) async {
    final id = await showDialog<String>(
      context: context,
      builder: (context) {
        final slots = _availableSlots(context);
        return SimpleDialog(
          title: Text('Ajouter un slot dans ${zone.label}'),
          children: [
            if (!slots.any((slot) => slot.visible))
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Aucun slot visible disponible.'),
              ),
            for (final slot in slots)
              if (slot.visible)
                SimpleDialogOption(
                  key: ValueKey('super-layout-add-slot-${slot.id}'),
                  onPressed: () => Navigator.of(context).pop(slot.id),
                  child: Text(slot.label),
                ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
          ],
        );
      },
    );
    if (id == null || !mounted) return;
    final config = _config.value;
    _update(config.withSlotMoved(id, config.contentZone(zone)));
  }

  List<SlotImplementation> _availableSlots(BuildContext context) {
    final registry = SuperApp.maybeOf(context)?.registry;
    final ids = {for (final slot in widget.slots) slot.id};
    return [
      ...widget.slots,
      if (registry != null)
        for (final entry in registry.registry.entries)
          BuilderSlot(
            id: _registrySlotId(entry.key, ids),
            label: 'Registre : ${entry.key}',
            builder: (_) => entry.value,
          ),
    ];
  }

  String _registrySlotId(String key, Set<String> slotIds) {
    var id = 'registry:${Uri.encodeComponent(key)}';
    while (slotIds.contains(id)) {
      id = 'registry:$id';
    }
    return id;
  }

  /// Slots visibles rangés dans la zone de contenu [content], dans l'ordre de
  /// [SuperLayoutConfig.placements] ; un identifiant inconnu est ignoré.
  List<SlotImplementation> _slotsOf(
    SuperLayoutConfig config,
    SuperLayoutZone content,
  ) {
    final ids = config.placementsOf(content);
    if (ids.isEmpty) return const [];
    final byId = {for (final slot in _availableSlots(context)) slot.id: slot};
    return [
      for (final id in ids)
        if (byId[id] case final slot? when slot.visible) slot,
    ];
  }

  bool _hasContent(SuperLayoutConfig config, SuperLayoutZone content) =>
      _slotsOf(config, content).isNotEmpty;

  Widget _contentOf(
    SuperLayoutConfig config,
    SuperLayoutZone zone,
    Set<SuperLayoutZone> autoSides,
    bool editMode,
  ) {
    final content = config.contentZone(zone);
    final slots = _slotsOf(config, content);
    if (slots.isEmpty) return _ZonePlaceholder(zone: zone);
    final auto = autoSides.contains(zone);
    return SlotStack(
      slots: slots,
      showLabels: editMode,
      emphasis: _emphasisFor(zone),
      zoneLabel: zone.label,
      mover: editMode && widget.editable
          ? SlotMover(
              owner: this,
              onMove: (id, {beforeId, afterId}) => _update(
                _config.value.withSlotMoved(
                  id,
                  content,
                  beforeId: beforeId,
                  afterId: afterId,
                ),
              ),
            )
          : null,
      expand:
          !(auto &&
              (zone == SuperLayoutZone.north || zone == SuperLayoutZone.south)),
      stretch:
          !(auto &&
              (zone == SuperLayoutZone.west || zone == SuperLayoutZone.east)),
    );
  }

  @override
  Widget build(BuildContext context) => SuperContainer(
    decorate: false,
    label: widget.label,
    editable: widget.editable,
    onEdit: _openEditor,
    child: ListenableBuilder(
      listenable: Listenable.merge([_config, _selected]),
      builder: (context, _) {
        final config = _config.value;
        // Une disposition imbriquée n'affiche ses étiquettes que si la zone
        // qui la contient est sélectionnée dans sa disposition parente.
        final editMode =
            (StyleEditScope.controllerOf(context)?.value ?? false) &&
            _LabelScope.of(context);
        final parentPath = _LabelScope.pathOf(context);
        final selected = _selected.value;
        final name = widget.name ?? widget.label;
        // Une disposition sans sélection et sans parent sélectionné n'apporte
        // rien au chemin.
        _reportPath(
          editMode && (parentPath.isNotEmpty || selected != null)
              ? [...parentPath, name, if (selected != null) selected.label]
              : const [],
        );
        final editing = widget.showZoneNames && editMode;
        final zones = config.visibleZones;
        // Un côté automatique sans contenu garde sa taille fixe.
        final autoSides = {
          for (final side in config.autoSides)
            if (zones.contains(side) &&
                _hasContent(config, config.contentZone(side)))
              side,
        };
        return _ZoneLayout(
          config: config,
          autoSides: autoSides,
          children: [
            for (final zone in zones)
              _ZoneEntry(
                key: ValueKey('super-layout-${zone.name}'),
                zone: zone,
                child: _LabelScope(
                  visible: editMode && selected == zone,
                  path: [...parentPath, name, zone.label],
                  child: _contentOf(config, zone, autoSides, editMode),
                ),
              ),
            // Une zone reçoit un slot glissé sur sa partie libre : il s'y range
            // en dernier.
            if (editMode && widget.editable)
              for (final zone in zones)
                _ZoneEntry(
                  key: ValueKey('super-layout-slot-drop-${zone.name}'),
                  zone: zone,
                  overlay: true,
                  dropTarget: true,
                  child: _SlotZoneTarget(
                    owner: this,
                    zoneLabel: zone.label,
                    ids: [
                      for (final slot in _slotsOf(
                        config,
                        config.contentZone(zone),
                      ))
                        slot.id,
                    ],
                    onMove: (id) => _update(
                      config.withSlotMoved(id, config.contentZone(zone)),
                    ),
                  ),
                ),
            // Noms des zones utilisées, au-dessus de leur centre.
            if (editing) ...[
              _ZoneEntry(
                key: const ValueKey('super-layout-center-target'),
                zone: SuperLayoutZone.center,
                overlay: true,
                dropTarget: true,
                child: _CenterSwapTarget(
                  overCenter: _overCenter,
                  hint: _centerHint,
                  canSwap: (zone) =>
                      widget.editable &&
                      zones.contains(zone) &&
                      config.canSwap(zone),
                  onSwap: (zone) => _update(config.withSwap(zone)),
                ),
              ),
              for (final zone in zones)
                if (_hasContent(config, config.contentZone(zone)))
                  _ZoneEntry(
                    key: ValueKey('super-layout-name-${zone.name}'),
                    zone: zone,
                    overlay: true,
                    child: _ZoneNameBadge(
                      zone: zone,
                      overCenter: _overCenter,
                      onCenterHint: (active) => _hintCenter(zone, active),
                      emphasis: _emphasisFor(zone),
                      selected: selected == zone,
                      onSelect: () => _select(zone),
                      swapTarget: widget.editable && config.canSwap(zone)
                          ? zone.opposite
                          : null,
                      moves: !zones.contains(zone.opposite),
                      onSwap: () => _update(config.withSwap(zone)),
                    ),
                  )
                else if (widget.editable)
                  _ZoneEntry(
                    key: ValueKey('super-layout-add-overlay-${zone.name}'),
                    zone: zone,
                    overlay: true,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: IconButton.filled(
                          key: ValueKey('super-layout-add-${zone.name}'),
                          tooltip: 'Ajouter un slot dans ${zone.label}',
                          icon: const Icon(Icons.add),
                          onPressed: () => _addSlot(zone),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        );
      },
    ),
  );
}

/// Indique si les étiquettes d'édition des dispositions situées dessous sont
/// visibles ; la disposition racine les montre toujours.
class _LabelScope extends InheritedWidget {
  const _LabelScope({
    required this.visible,
    required this.path,
    required super.child,
  });

  final bool visible;

  /// Zones sélectionnées au-dessus de ces dispositions, de la plus englobante
  /// à la plus proche.
  final List<String> path;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LabelScope>()?.visible ??
      true;

  static List<String> pathOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LabelScope>()?.path ??
      const [];

  @override
  bool updateShouldNotify(_LabelScope oldWidget) =>
      visible != oldWidget.visible || !listEquals(path, oldWidget.path);
}

class _ZoneParentData extends ContainerBoxParentData<RenderBox> {
  SuperLayoutZone? zone;

  /// Un calque épouse le rectangle de sa zone sans compter dans sa mesure.
  bool overlay = false;

  /// Cible de dépôt : testée après le contenu, pour qu'une cible imbriquée soit
  /// consultée avant celle de la disposition qui la contient.
  bool dropTarget = false;
}

/// Rattache un enfant de [_ZoneLayout] à une zone.
class _ZoneEntry extends ParentDataWidget<_ZoneParentData> {
  const _ZoneEntry({
    required this.zone,
    required super.child,
    this.overlay = false,
    this.dropTarget = false,
    super.key,
  });

  final SuperLayoutZone zone;
  final bool overlay;
  final bool dropTarget;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ZoneParentData;
    if (data.zone == zone &&
        data.overlay == overlay &&
        data.dropTarget == dropTarget) {
      return;
    }
    data
      ..zone = zone
      ..overlay = overlay
      ..dropTarget = dropTarget;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _ZoneLayout;
}

/// Place les enfants dans les rectangles de [SuperLayoutConfig.resolve]. Les
/// côtés de [autoSides] sont d'abord mesurés (largeur de l'Ouest et de l'Est,
/// puis hauteur du Nord et du Sud), le centre reçoit le reste.
class _ZoneLayout extends MultiChildRenderObjectWidget {
  const _ZoneLayout({
    required this.config,
    required this.autoSides,
    required super.children,
  });

  final SuperLayoutConfig config;
  final Set<SuperLayoutZone> autoSides;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderZoneLayout(config, autoSides);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderZoneLayout renderObject,
  ) => renderObject
    ..config = config
    ..autoSides = autoSides;
}

class _RenderZoneLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ZoneParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ZoneParentData> {
  _RenderZoneLayout(this._config, this._autoSides);

  SuperLayoutConfig _config;
  set config(SuperLayoutConfig value) {
    if (value == _config) return;
    _config = value;
    markNeedsLayout();
  }

  Set<SuperLayoutZone> _autoSides;
  set autoSides(Set<SuperLayoutZone> value) {
    if (setEquals(value, _autoSides)) return;
    _autoSides = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ZoneParentData) {
      child.parentData = _ZoneParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final content = <SuperLayoutZone, RenderBox>{};
    final overlays = <(SuperLayoutZone, RenderBox)>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _ZoneParentData;
      final zone = data.zone!;
      if (data.overlay) {
        overlays.add((zone, child));
      } else {
        content[zone] = child;
      }
    }

    final measured = <SuperLayoutZone, double>{};
    for (final side in const [SuperLayoutZone.west, SuperLayoutZone.east]) {
      final child = content[side];
      if (child == null || !_autoSides.contains(side)) continue;
      child.layout(
        BoxConstraints(maxWidth: size.width, maxHeight: size.height),
        parentUsesSize: true,
      );
      measured[side] = child.size.width;
    }
    // La largeur du Nord et du Sud dépend de celle de l'Ouest et de l'Est.
    final widths = _config.resolve(size, measured: measured);
    for (final side in const [SuperLayoutZone.north, SuperLayoutZone.south]) {
      final child = content[side];
      final rect = widths[side];
      if (child == null || rect == null || !_autoSides.contains(side)) continue;
      child.layout(
        BoxConstraints(
          minWidth: rect.width,
          maxWidth: rect.width,
          maxHeight: size.height,
        ),
        parentUsesSize: true,
      );
      measured[side] = child.size.height;
    }

    final rects = _config.resolve(size, measured: measured);
    for (final (zone, child, overlay) in [
      for (final entry in content.entries) (entry.key, entry.value, false),
      for (final (zone, child) in overlays) (zone, child, true),
    ]) {
      final rect = rects[zone] ?? Rect.zero;
      final autoAxis = overlay || !measured.containsKey(zone)
          ? null
          : (zone == SuperLayoutZone.north || zone == SuperLayoutZone.south)
          ? Axis.vertical
          : Axis.horizontal;
      // L'axe automatique reste libre, avec la borne de la mesure : des
      // contraintes strictes feraient du contenu une frontière de layout (son
      // changement de taille n'atteindrait pas ce parent), et une autre borne
      // changerait la taille mesurée.
      child.layout(switch (autoAxis) {
        null => BoxConstraints.tight(rect.size),
        Axis.vertical => BoxConstraints(
          minWidth: rect.width,
          maxWidth: rect.width,
          maxHeight: size.height,
        ),
        Axis.horizontal => BoxConstraints(
          minHeight: rect.height,
          maxHeight: rect.height,
          maxWidth: size.width,
        ),
      }, parentUsesSize: autoAxis != null);
      (child.parentData! as _ZoneParentData).offset = rect.topLeft;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.pushClipRect(
    needsCompositing,
    offset,
    Offset.zero & size,
    defaultPaint,
  );

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var hit = false;
    final dropTargets = <RenderBox>[];
    bool hitChild(RenderBox child) => result.addWithPaintOffset(
      offset: (child.parentData! as _ZoneParentData).offset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
    for (var child = lastChild; child != null; child = childBefore(child)) {
      if ((child.parentData! as _ZoneParentData).dropTarget) {
        dropTargets.add(child);
      } else if (!hit && hitChild(child)) {
        hit = true;
      }
    }
    // Un DragTarget ne consulte pas une cible apparue après un rejet : les
    // cibles imbriquées doivent donc précéder celle qui les contient.
    for (final child in dropTargets) {
      if (hitChild(child)) hit = true;
    }
    return hit;
  }
}

/// Pastille du nom d'une zone, centrée sur celle-ci pendant le mode édition.
/// Un clic sur une zone ayant une opposée ([swapTarget]) révèle un bouton qui
/// échange leurs contenus, ou déplace la zone si l'opposée n'existe pas
/// ([moves]).
class _ZoneNameBadge extends StatefulWidget {
  const _ZoneNameBadge({
    required this.zone,
    required this.onSwap,
    required this.overCenter,
    required this.onCenterHint,
    required this.emphasis,
    required this.selected,
    required this.onSelect,
    this.swapTarget,
    this.moves = false,
  });

  final SuperLayoutZone zone;
  final SuperLayoutZone? swapTarget;
  final bool moves;
  final VoidCallback onSwap;
  final ValueListenable<bool> overCenter;

  /// Signale que ce nom est survolé ou glissé : le centre doit être surligné.
  final ValueChanged<bool> onCenterHint;
  final LabelEmphasis emphasis;

  /// La zone est sélectionnée ; un clic sur son nom la (dé)sélectionne.
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_ZoneNameBadge> createState() => _ZoneNameBadgeState();
}

class _ZoneNameBadgeState extends State<_ZoneNameBadge> {
  bool _open = false;

  /// Le nom est survolé ou glissé : la zone qu'il désigne est surlignée.
  bool _hover = false;
  bool _dragging = false;

  void _setHover(bool value) {
    if (mounted && value != _hover) {
      setState(() => _hover = value);
      _report();
    }
  }

  void _setDragging(bool value) {
    if (mounted && value != _dragging) {
      setState(() => _dragging = value);
      _report();
    }
  }

  void _report() {
    final active = _hover || _dragging;
    widget.emphasis.report(widget.zone, active);
    // Le centre n'a pas de centre associé : il se surligne lui-même.
    if (widget.zone != SuperLayoutZone.center) widget.onCenterHint(active);
  }

  @override
  void dispose() {
    if (_hover || _dragging) {
      // Le parent ne doit pas être notifié pendant le démontage.
      final zone = widget.zone;
      final emphasis = widget.emphasis;
      final centerHint = widget.onCenterHint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        emphasis.report(zone, false);
        if (zone != SuperLayoutZone.center) centerHint(false);
      });
    }
    super.dispose();
  }

  IconData get _icon => switch (widget.zone) {
    SuperLayoutZone.north || SuperLayoutZone.south => Icons.swap_vert,
    SuperLayoutZone.west || SuperLayoutZone.east => Icons.swap_horiz,
    _ => Icons.swap_calls,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final target = widget.swapTarget;
    final label = Text(
      widget.zone.label,
      style: TextStyle(fontSize: 11, color: colors.onPrimary),
    );
    final badge = Material(
      color: colors.primary.withValues(alpha: .85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.selected ? colors.onPrimary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: target == null
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: label,
            )
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _open = !_open);
                widget.onSelect();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 1, 4, 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label,
                    if (_open)
                      IconButton(
                        key: ValueKey('super-layout-swap-${widget.zone.name}'),
                        tooltip: widget.moves
                            ? 'Déplacer vers ${target.label}'
                            : 'Échanger avec ${target.label}',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        color: colors.onPrimary,
                        icon: Icon(_icon),
                        onPressed: () {
                          setState(() => _open = false);
                          widget.onSwap();
                        },
                      )
                    else
                      const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_hover || _dragging)
          Positioned.fill(
            key: ValueKey('super-layout-zone-highlight-${widget.zone.name}'),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  border: Border.all(color: colors.primary, width: 2),
                ),
              ),
            ),
          ),
        if (widget.selected)
          Positioned.fill(
            key: ValueKey('super-layout-zone-selected-${widget.zone.name}'),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.primary, width: 3),
                ),
              ),
            ),
          ),
        Center(
          key: const ValueKey('super-layout-zone-badge'),
          child: EmphasizedLabel(
            emphasis: widget.emphasis,
            allScopes: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: MouseRegion(
                hitTestBehavior: HitTestBehavior.translucent,
                onEnter: (_) => _setHover(true),
                onExit: (_) => _setHover(false),
                // Glisser le nom vers le centre déclenche l'échange.
                child: target == null
                    ? GestureDetector(onTap: widget.onSelect, child: badge)
                    : Draggable<SuperLayoutZone>(
                        onDragStarted: () => _setDragging(true),
                        onDragEnd: (_) => _setDragging(false),
                        data: widget.zone,
                        feedback: Material(
                          color: colors.primary,
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            // Pendant le survol du centre, le nom devient la zone future.
                            child: ValueListenableBuilder<bool>(
                              valueListenable: widget.overCenter,
                              builder: (context, over, _) => Text(
                                over ? target.label : widget.zone.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: .35, child: badge),
                        child: badge,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cible de dépôt sur le centre : illuminée pendant qu'un nom de zone la
/// survole, elle échange alors cette zone avec son opposée au relâchement.
class _CenterSwapTarget extends StatelessWidget {
  const _CenterSwapTarget({
    required this.canSwap,
    required this.onSwap,
    required this.overCenter,
    required this.hint,
  });

  final ValueNotifier<bool> overCenter;

  /// Le nom d'une autre zone est survolé : le centre est mis en évidence.
  final ValueListenable<bool> hint;
  final bool Function(SuperLayoutZone zone) canSwap;
  final ValueChanged<SuperLayoutZone> onSwap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<SuperLayoutZone>(
      onWillAcceptWithDetails: (details) {
        final accept = canSwap(details.data);
        overCenter.value = accept;
        return accept;
      },
      onLeave: (_) => overCenter.value = false,
      onAcceptWithDetails: (details) {
        overCenter.value = false;
        onSwap(details.data);
      },
      builder: (context, candidates, _) => IgnorePointer(
        child: candidates.isEmpty
            ? ValueListenableBuilder<bool>(
                valueListenable: hint,
                builder: (context, hinted, _) => hinted
                    ? DecoratedBox(
                        key: const ValueKey('super-layout-center-hint'),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .08),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: .7),
                            width: 1.5,
                          ),
                        ),
                        child: const SizedBox.expand(),
                      )
                    : const SizedBox.expand(),
              )
            : DecoratedBox(
                key: const ValueKey('super-layout-center-drop'),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .2),
                  border: Border.all(color: colors.primary, width: 2),
                ),
              ),
      ),
    );
  }
}

/// Cible de dépôt d'une zone entière pour les slots de son propriétaire.
class _SlotZoneTarget extends StatelessWidget {
  const _SlotZoneTarget({
    required this.owner,
    required this.zoneLabel,
    required this.ids,
    required this.onMove,
  });

  final Object owner;
  final String zoneLabel;

  /// Slots visibles de la zone, dans l'ordre.
  final List<String> ids;
  final ValueChanged<String> onMove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DragTarget<SlotDragData>(
      onWillAcceptWithDetails: (details) {
        final accepts = identical(details.data.owner, owner);
        if (accepts) {
          details.data.hint.value = SlotDropHint.at(
            zoneLabel: zoneLabel,
            ids: ids,
            movedId: details.data.id,
          );
        }
        return accepts;
      },
      onLeave: (data) => data?.hint.value = null,
      onAcceptWithDetails: (details) => onMove(details.data.id),
      builder: (context, candidates, _) => IgnorePointer(
        child: candidates.isEmpty
            ? const SizedBox.expand()
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.tertiary.withValues(alpha: .15),
                  border: Border.all(color: colors.tertiary, width: 2),
                ),
              ),
      ),
    );
  }
}

class _ZonePlaceholder extends StatelessWidget {
  const _ZonePlaceholder({required this.zone});

  final SuperLayoutZone zone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Center(
        child: Text(
          zone.label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Formulaire d'édition d'un [SuperLayoutConfig] : aperçu, présence des côtés,
/// fusion des coins et tailles.
class SuperLayoutEditor extends StatelessWidget {
  const SuperLayoutEditor({
    required this.config,
    required this.onChanged,
    super.key,
  });

  final SuperLayoutConfig config;
  final ValueChanged<SuperLayoutConfig> onChanged;

  static const _sides = [
    SuperLayoutZone.north,
    SuperLayoutZone.south,
    SuperLayoutZone.west,
    SuperLayoutZone.east,
  ];
  static const _corners = [
    SuperLayoutZone.nw,
    SuperLayoutZone.ne,
    SuperLayoutZone.sw,
    SuperLayoutZone.se,
  ];

  static double _size(SuperLayoutConfig config, SuperLayoutZone side) =>
      switch (side) {
        SuperLayoutZone.north => config.northSize,
        SuperLayoutZone.south => config.southSize,
        SuperLayoutZone.west => config.westSize,
        _ => config.eastSize,
      };

  SuperLayoutConfig _withSize(SuperLayoutZone side, double value) =>
      switch (side) {
        SuperLayoutZone.north => config.copyWith(northSize: value),
        SuperLayoutZone.south => config.copyWith(southSize: value),
        SuperLayoutZone.west => config.copyWith(westSize: value),
        _ => config.copyWith(eastSize: value),
      };

  /// Voisins d'un coin : (zone de sa ligne, zone de sa colonne).
  static (SuperLayoutZone, SuperLayoutZone) _neighbors(
    SuperLayoutZone corner,
  ) => switch (corner) {
    SuperLayoutZone.nw => (SuperLayoutZone.north, SuperLayoutZone.west),
    SuperLayoutZone.ne => (SuperLayoutZone.north, SuperLayoutZone.east),
    SuperLayoutZone.sw => (SuperLayoutZone.south, SuperLayoutZone.west),
    _ => (SuperLayoutZone.south, SuperLayoutZone.east),
  };

  static String _mergeLabel(SuperLayoutZone corner, CornerMerge merge) {
    final (row, column) = _neighbors(corner);
    return switch (merge) {
      CornerMerge.none => 'Case propre',
      CornerMerge.row => 'Fusionné avec ${row.label}',
      CornerMerge.column => 'Fusionné avec ${column.label}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = config.copyWith(
      northSize: 36,
      southSize: 36,
      westSize: 70,
      eastSize: 70,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('super-layout-preview'),
          height: 170,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                for (final MapEntry(key: zone, value: rect)
                    in preview.resolve(constraints.biggest).entries)
                  Positioned.fromRect(
                    key: ValueKey('super-layout-preview-${zone.name}'),
                    rect: rect.deflate(1),
                    child: ColoredBox(
                      color: colors.primaryContainer,
                      child: Center(
                        child: Text(
                          zone.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final side in _sides) ...[
          SwitchListTile(
            key: ValueKey('super-layout-side-${side.name}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(side.label),
            value: config.hasSide(side),
            onChanged: (v) => onChanged(config.withSide(side, v)),
          ),
          if (config.hasSide(side))
            SwitchListTile(
              key: ValueKey('super-layout-auto-${side.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Taille automatique'),
              value: config.isAuto(side),
              onChanged: (v) => onChanged(config.withAuto(side, v)),
            ),
          if (config.hasSide(side) && !config.isAuto(side))
            Slider(
              key: ValueKey('super-layout-size-${side.name}'),
              min: SuperLayoutConfig.minSize,
              max: SuperLayoutConfig.maxSize,
              value: _size(
                config,
                side,
              ).clamp(SuperLayoutConfig.minSize, SuperLayoutConfig.maxSize),
              label: '${_size(config, side).round()}',
              onChanged: (v) => onChanged(_withSize(side, v)),
            ),
        ],
        const Divider(),
        for (final corner in _corners)
          Row(
            children: [
              Expanded(child: Text(corner.label)),
              DropdownButton<CornerMerge>(
                key: ValueKey('super-layout-corner-${corner.name}'),
                value: config.mergeOf(corner),
                onChanged: config.cornerExists(corner)
                    ? (v) => onChanged(config.withCorner(corner, v!))
                    : null,
                items: [
                  for (final merge in CornerMerge.values)
                    DropdownMenuItem(
                      value: merge,
                      child: Text(_mergeLabel(corner, merge)),
                    ),
                ],
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(
            const SuperLayoutConfig().copyWith(placements: config.placements),
          ),
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
