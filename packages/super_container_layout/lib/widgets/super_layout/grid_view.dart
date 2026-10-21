part of 'super_layout.dart';

extension _SuperLayoutGrid on SuperLayoutState {
  Widget _buildGrid(BuildContext context) {
    final editing =
        (StyleEditScope.controllerOf(context)?.value ?? false) &&
        identical(_LayoutEditSelection.selected.value, this);
    final parentPath = _LabelScope.pathOf(context);
    final name =
        _config.value.label != null ||
            (editorComponentLabelOf(context)?.overridden ?? false)
        ? _displayLabel
        : widget.name ?? widget.label;
    final slots = [
      for (final id in _config.value.placedSlotIds)
        if (searchSlot(id) case final slot? when slot.visible) slot,
    ];
    final selected = slots
        .where((slot) => slot.id == _selectedSlot.value)
        .firstOrNull;
    LayoutSelection.register(
      this,
      [...parentPath, name],
      (label) {
        _selected.value = null;
        _selectedSlot.value =
            (slots
                        .where(
                          (slot) =>
                              slot.id == _selectedSlot.value &&
                              slot.label == label,
                        )
                        .firstOrNull ??
                    slots.where((slot) => slot.label == label).firstOrNull)
                ?.id;
        _LayoutEditSelection.activate(this);
      },
      parent:
          this.context.findAncestorStateOfType<SuperLayoutState>() ??
          LayoutSelectionScope.of(context)?.owner,
      onDeselect: () {
        _selectedSlot.value = null;
        _selected.value = null;
        if (identical(_LayoutEditSelection.selected.value, this)) {
          _LayoutEditSelection.selected.value = null;
        }
      },
    );
    _reportPath(
      editing
          ? [...parentPath, name, if (selected != null) selected.label]
          : const [],
    );
    return EditorSelectionRegion(
      enabled: StyleEditScope.controllerOf(context)?.value ?? false,
      isZone: true,
      selected: editing && selected == null,
      onSelect: () {
        _selected.value = null;
        _selectedSlot.value = null;
        _LayoutEditSelection.activate(this);
      },
      child: _GridSurface(
        owner: this,
        slots: slots,
        config: _config.value.effectiveGrid,
        editing: editing,
        path: [...parentPath, name],
      ),
    );
  }
}

class _GridSurface extends StatefulWidget {
  const _GridSurface({
    required this.owner,
    required this.slots,
    required this.config,
    required this.editing,
    required this.path,
  });
  final SuperLayoutState owner;
  final List<SlotImplementation> slots;
  final GridLayoutConfig config;
  final bool editing;
  final List<String> path;

  @override
  State<_GridSurface> createState() => _GridSurfaceState();
}

class _GridSurfaceState extends State<_GridSurface> {
  final _canvas = GlobalKey();
  final _viewport = GlobalKey();
  final _hoveredLabels = <String>{};
  String? _dragId;
  Offset? _startPoint;
  SuperLayoutConfig? _initial;
  EditorHistoryController? _history;
  EditorZoomController? _zoom;
  double _columnStep = 1;
  double _rowStep = 1;
  void _select(String id) {
    widget.owner._selected.value = null;
    widget.owner._selectedSlot.value = id;
    _LayoutEditSelection.activate(widget.owner);
  }

  void _start(String id, DragStartDetails details) {
    final box = _canvas.currentContext!.findRenderObject()! as RenderBox;
    _initial = widget.owner.config.copyWith(grid: widget.config);
    _startPoint = box.globalToLocal(details.globalPosition);
    _history = EditorHistoryScope.controllerOf(context);
    _history?.beginTransaction();
    _zoom = EditorZoomScope.controllerOf(context);
    _zoom?.beginInteraction();
    _select(id);
    setState(() => _dragId = id);
  }

  void _drag(DragUpdateDetails details, Alignment? direction) {
    final initial = _initial;
    final id = _dragId;
    if (initial == null || id == null || !widget.owner.mounted) return;
    final box = _canvas.currentContext!.findRenderObject()! as RenderBox;
    final delta = box.globalToLocal(details.globalPosition) - _startPoint!;
    final dx = (delta.dx / _columnStep).round();
    final dy = (delta.dy / _rowStep).round();
    final grid = initial.grid!;
    final p = grid.items[id]!;
    GridSlotPosition next;
    if (direction == null) {
      next = p.copyWith(
        x: (p.x + dx).clamp(0, grid.columns - p.width),
        y: (p.y + dy).clamp(0, 10000),
      );
    } else {
      var left = p.x;
      var right = p.x + p.width;
      var top = p.y;
      var bottom = p.y + p.height;
      if (direction.x < 0) left = (left + dx).clamp(0, right - 1);
      if (direction.x > 0) right = (right + dx).clamp(left + 1, grid.columns);
      if (direction.y < 0) top = (top + dy).clamp(0, bottom - 1);
      if (direction.y > 0) bottom = (bottom + dy).clamp(top + 1, top + 10000);
      next = GridSlotPosition(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
    }
    widget.owner._update(
      widget.owner.config.copyWith(
        grid: grid.withItem(id, next, compact: false),
      ),
    );
    setState(() {});
  }

  void _end() {
    if (_dragId == null) return;
    widget.owner._update(
      widget.owner.config.copyWith(
        grid: widget.owner.config.effectiveGrid.arrange(activeId: _dragId),
      ),
    );
    _history?.commitTransaction();
    _history = null;
    _zoom?.endInteraction();
    _zoom = null;
    _initial = null;
    _startPoint = null;
    setState(() => _dragId = null);
  }

  @override
  void dispose() {
    _history?.commitTransaction();
    _zoom?.endInteraction();
    super.dispose();
  }

  Widget _controls(SlotImplementation slot) {
    final owner = widget.owner;
    final selected = owner._selectedSlot.value == slot.id;
    final p = widget.config.items[slot.id]!;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: _dragId == slot.id
                    ? const ValueKey('grid-drop-preview')
                    : null,
                decoration: BoxDecoration(
                  color: _dragId == slot.id
                      ? colors.tertiary.withValues(alpha: .12)
                      : null,
                  border: Border.all(color: colors.tertiary, width: 2),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 36, left: 32, right: 32),
              child: GestureDetector(
                key: ValueKey('grid-slot-label-${slot.id}'),
                dragStartBehavior: DragStartBehavior.down,
                onTap: () => _select(slot.id),
                onPanStart: owner.widget.editable
                    ? (d) => _start(slot.id, d)
                    : null,
                onPanUpdate: owner.widget.editable
                    ? (d) => _drag(d, null)
                    : null,
                onPanEnd: owner.widget.editable ? (_) => _end() : null,
                onPanCancel: owner.widget.editable ? _end : null,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveredLabels.add(slot.id)),
                  onExit: (_) => setState(() => _hoveredLabels.remove(slot.id)),
                  cursor: owner.widget.editable
                      ? editorDragCursor(dragging: _dragId == slot.id)
                      : SystemMouseCursors.click,
                  child: Tooltip(
                    message: 'Glisser pour déplacer ${slot.label}',
                    child: ComponentDragLabel(
                      draggable: owner.widget.editable,
                      dragging: _dragId == slot.id,
                      highlighted: _hoveredLabels.isNotEmpty || _dragId != null,
                      child: Text(slot.label),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (selected && owner.widget.editable)
          for (final (name, direction) in editorResizeDirections)
            Positioned.fill(
              child: Align(
                alignment: direction,
                child: EditorResizeHandle(
                  key: ValueKey('slot-resize-${slot.id}-$name'),
                  direction: direction,
                  label: slot.label,
                  onStart: (d) => _start(slot.id, d),
                  onUpdate: (d) => _drag(d, direction),
                  onEnd: _end,
                ),
              ),
            ),
        if (_dragId == slot.id)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  color: colors.tertiaryContainer,
                  child: Text(
                    '${p.width} × ${p.height} cellules',
                    key: ValueKey('grid-slot-size-${slot.id}'),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final grid = widget.config;
      grid.validate();
      final width = constraints.maxWidth;
      // Gaps scale down on very narrow viewports, keeping all columns visible.
      final gap = math.min(grid.gap, width / (grid.columns * 2));
      _columnStep = (width + gap) / grid.columns;
      _rowStep = grid.rowHeight + gap;
      final rows = grid.items.values.fold<int>(
        0,
        (maximum, p) => math.max(maximum, p.y + p.height),
      );
      final height = math.max(constraints.maxHeight, rows * _rowStep - gap);
      Rect rect(GridSlotPosition p) => Rect.fromLTWH(
        p.x * _columnStep,
        p.y * _rowStep,
        p.width * _columnStep - gap,
        p.height * _rowStep - gap,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            key: _viewport,
            child: SingleChildScrollView(
              key: const ValueKey('super-layout-grid-scroll'),
              child: SizedBox(
                key: _canvas,
                width: width,
                height: height,
                child: Stack(
                  children: [
                    if (widget.editing)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _GridPainter(
                              columns: grid.columns,
                              columnStep: _columnStep,
                              rowStep: _rowStep,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                        ),
                      ),
                    for (final slot in widget.slots)
                      Positioned.fromRect(
                        key: ValueKey('grid-position-${slot.id}'),
                        rect: rect(grid.items[slot.id]!),
                        child: EditorSlotAction(
                          label: 'Position et taille : ${slot.label}',
                          enabled:
                              widget.owner.widget.editable &&
                              (StyleEditScope.controllerOf(context)?.value ??
                                  false),
                          inline: true,
                          onEdit: () => widget.owner._editGridSlot(slot),
                          onRemove: () async =>
                              widget.owner._removeSlot(slot.id),
                          wrapActions: widget.owner._wrapActionsForSlot(slot),
                          child: Builder(
                            builder: (context) => _LabelScope(
                              path: [...widget.path, slot.label],
                              child: KeyedSubtree(
                                key: widget.owner._slotFocusKeys.putIfAbsent(
                                  slot.id,
                                  GlobalKey.new,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  excludeFromSemantics: true,
                                  onSecondaryTapUp:
                                      widget.owner.widget.editable &&
                                          (StyleEditScope.controllerOf(context)
                                                  ?.value ??
                                              false)
                                      ? (d) => context
                                            .findAncestorStateOfType<
                                              EditorSlotState
                                            >()
                                            ?.openMenu(
                                              d.globalPosition,
                                              actions: EditorSlotAction.of(
                                                context,
                                              ),
                                            )
                                      : null,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      EditorSelectionRegion(
                                        selected:
                                            widget.editing &&
                                            widget.owner._selectedSlot.value ==
                                                slot.id,
                                        enabled:
                                            StyleEditScope.controllerOf(context)
                                                ?.value ??
                                            false,
                                        onSelect: () => _select(slot.id),
                                        child: SlotStack(
                                          slots: [slot],
                                          focusKeys:
                                              widget.owner._gridSlotSizeKeys,
                                          preferredSizes: widget
                                              .owner
                                              .config
                                              .slotPreferredSizes,
                                          sizeConstraints: widget
                                              .owner
                                              .config
                                              .slotSizeConstraints,
                                          layoutSize: Size(
                                            width,
                                            constraints.maxHeight,
                                          ),
                                        ),
                                      ),
                                      if (widget.editing)
                                        Positioned.fill(
                                          child: EditorOverlay(
                                            clipKey: _viewport,
                                            child: _controls(slot),
                                          ),
                                        ),
                                    ],
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
          ),
          if (widget.editing && widget.owner.widget.editable)
            Positioned.fill(
              child: EditorOverlay(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton.filled(
                      key: const ValueKey('grid-add-slot'),
                      tooltip: 'Ajouter un slot dans la grille',
                      onPressed: () =>
                          widget.owner._addSlot(SuperLayoutZone.center),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.columns,
    required this.columnStep,
    required this.rowStep,
    required this.color,
  });
  final int columns;
  final double columnStep;
  final double rowStep;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .5)
      ..strokeWidth = 1;
    for (var x = 0; x <= columns; x++) {
      canvas.drawLine(
        Offset(x * columnStep, 0),
        Offset(x * columnStep, size.height),
        paint,
      );
    }
    final clip = canvas.getLocalClipBounds();
    final firstRow = math.max(0, (clip.top / rowStep).floor()) * rowStep;
    for (
      var y = firstRow;
      y <= math.min(size.height, clip.bottom);
      y += rowStep
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      columns != oldDelegate.columns ||
      columnStep != oldDelegate.columnStep ||
      rowStep != oldDelegate.rowStep ||
      color != oldDelegate.color;
}
