// Rendu des slots, régions Box/Sliver et overlays d'édition de [NativeComponentEditorState].
part of '../native_component_editor.dart';

/// Extension gérant la construction des widgets de régions, slots et Slivers de [NativeComponentEditorState].
extension NativeComponentEditorRegions on NativeComponentEditorState {
  bool _showOverlay() =>
      editing && _active && identical(LayoutSelection.activeOwner, this);

  void _setRegionHovered(String id, bool hovered) {
    if (!mounted) return;
    final scopes = {..._hoveredRegionScopes.value};
    final changed = hovered ? scopes.add(id) : scopes.remove(id);
    if (!changed) return;
    _setEditorState(() => _hoveredRegionScopes.value = scopes);
  }

  /// Enveloppe un unique [slot] de la région [id] avec ses actions d'édition,
  /// sa sélection et son réordonnancement par glisser-déposer sans dupliquer
  /// l'[EditorSlot] externe ni le badge de zone.
  Widget slotItem(String id, SlotImplementation slot) {
    final spec = definition(id);
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
    return SlotStack(
      slots: [slot],
      focusKeys: _slotKeys,
      regionSlotIds: [for (final item in slotsFor(id)) item.id],
      axis: spec.axis,
      expand: false,
      stretch: spec.stretch,
      emphasis: emphasis,
      preferredSizes: {
        if (slot case NativePreferredSizeWidget native)
          slot.id: native.preferredSizeIn(context),
        ...widget.config.slotPreferredSizes,
      },
      sizeConstraints: widget.config.slotSizeConstraints,
      layoutSize: _layoutSize,
      showLabels: overlay,
      zoneLabel: spec.label,
      selectedSlotId: selected ? _selectedSlot : null,
      onSelectSlot: editing && widget.editSurface
          ? (slot) => _toggleSlot(id, slot)
          : null,
      onSelectContent: editing ? (slot) => _selectSlot(id, slot) : null,
      canSelectSlot: _canSelectSlot,
      onResizeSlot: editing && widget.editSurface
          ? (slot, dimensions) => _update(
              _config.value.withSlotSizeConstraints(slot.id, dimensions),
            )
          : null,
      mover: editing
          ? SlotMover(
              owner: this,
              canMove: (slotId) => _canMoveSlot(slotId, id),
              onMove: (slotId, {beforeId, afterId}) =>
                  _moveSlot(slotId, id, beforeId: beforeId, afterId: afterId),
            )
          : null,
      onRemoveSlot: editing
          ? (slot) async {
              if (widget.onSlotRemoved != null) {
                await widget.onSlotRemoved!(id, slot);
                return;
              }
              removeSlotInstance(
                context,
                id: slot.id,
                type: _config.value.slotTypeOf(slot.id),
                containerKind: EditorConfigKind.nativeComponent,
                unplace: () => _update(_config.value.withoutSlot(slot.id)),
              );
            }
          : null,
      onEditPreferredSize: editing ? _editSize : null,
      dimensionDelegateForSlot: editing ? _buildSlotSizeDelegate : null,
      wrapActionsForSlot: editing
          ? (slot) => wrapActionsForSlot(id, slot)
          : null,
      insertionForSlot: editing ? (slot) => insertionForSlot(id, slot) : null,
    );
  }

  /// Rend un unique [slot] de la région [id] sous forme de Sliver :
  /// - Si [slot] peut se rendre nativement en Sliver (`SuperAppBar`, `SuperListView`,
  ///   ou un widget `Sliver*` Flutter), il est construit dans un [SliverSlotScope]
  ///   avec ses actions d'édition et sa sélection.
  /// - Sinon, il est enveloppé dans un [SliverToBoxAdapter] contenant [slotItem].
  Widget sliverSlotItem(
    String id,
    SlotImplementation slot, {
    required Axis scrollDirection,
  }) {
    if (slot.canRenderAsSliver(context)) {
      final selectable = _canSelectSlot(slot);
      final actionLabel = 'Taille et marge préférées : ${slot.label}';
      final constraints = widget.config.slotSizeConstraints[slot.id];
      final preferredSize = preferredSizeFor(slot);
      final padding = constraints?.contentPadding ?? EdgeInsets.zero;
      Widget sliver = SliverSlotScope(
        enabled: true,
        scrollDirection: scrollDirection,
        preferredSize: preferredSize,
        child: EditorSlotAction(
          key: ValueKey('slot-item-${slot.id}'),
          label: actionLabel,
          tooltip: formatSlotSizeTooltip(
            title: actionLabel,
            constraints: constraints,
            preferredSize: preferredSize,
          ),
          inline: true,
          fixedWidth: hasFixedSlotWidth(
            constraints: constraints,
            preferredSize: preferredSize,
          ),
          fixedHeight: hasFixedSlotHeight(
            constraints: constraints,
            preferredSize: preferredSize,
          ),
          enabled: editing,
          showEdit: editing,
          onSelect: editing && selectable ? () => _selectSlot(id, slot) : null,
          onEdit: () async => _editSize(slot),
          dimensionDelegateBuilder: editing
              ? () => _buildSlotSizeDelegate(slot)
              : null,
          onRemove: editing
              ? () async {
                  if (widget.onSlotRemoved != null) {
                    await widget.onSlotRemoved!(id, slot);
                    return;
                  }
                  removeSlotInstance(
                    context,
                    id: slot.id,
                    type: _config.value.slotTypeOf(slot.id),
                    containerKind: EditorConfigKind.nativeComponent,
                    unplace: () => _update(_config.value.withoutSlot(slot.id)),
                  );
                }
              : null,
          wrapActions: editing
              ? wrapActionsForSlot(id, slot)
              : const <EditorSlotWrapAction>[],
          insertion: editing ? insertionForSlot(id, slot) : null,
          child: KeyedSubtree(
            key: _slotKeys.putIfAbsent('${slot.id}:sliver', GlobalKey.new),
            child: EditorSelectionRegion(
              enabled: editing && selectable,
              selected: _selected == id && _selectedSlot == slot.id,
              onSelect: () => _selectSlot(id, slot),
              child: slot,
            ),
          ),
        ),
      );
      if (padding != EdgeInsets.zero) {
        sliver = SliverPadding(padding: padding, sliver: sliver);
      }
      return sliver;
    }
    return SliverToBoxAdapter(
      child: SlotContentFitScope(
        fitWidth: scrollDirection == Axis.horizontal,
        fitHeight: scrollDirection == Axis.vertical,
        child: slotItem(id, slot),
      ),
    );
  }

  /// Rend la région [id] sous forme de Sliver (pour utilisation dans un `CustomScrollView`).
  Widget sliverRegion(
    String id, {
    required Axis scrollDirection,
    bool fillWhenEmpty = false,
  }) {
    final spec = definition(id);
    final slots = slotsFor(id);
    if (slots.isEmpty && !fillWhenEmpty) {
      if (!editing) {
        return const SliverToBoxAdapter(child: SizedBox.shrink());
      }
      final fallbackHeight =
          sizeOf(id) ??
          (spec.emptySize.height.isFinite
              ? spec.emptySize.height
              : kToolbarHeight);
      return SliverToBoxAdapter(
        child: SizedBox(height: fallbackHeight, child: region(id)),
      );
    }
    final selected = _selected == id;
    final regionFlow = flowOf(id);
    final spacing = regionFlow.spacing;
    final padding = regionFlow.contentPadding;
    final slivers = <Widget>[];
    for (final (index, slot) in slots.indexed) {
      if (index > 0 && spacing > 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: SizedBox(
              width: scrollDirection == Axis.horizontal ? spacing : null,
              height: scrollDirection == Axis.vertical ? spacing : null,
            ),
          ),
        );
      }
      slivers.add(sliverSlotItem(id, slot, scrollDirection: scrollDirection));
    }
    Widget content = slivers.isEmpty
        ? const SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.expand(),
          )
        : slivers.length == 1
        ? slivers.single
        : SliverMainAxisGroup(slivers: slivers);
    if (padding != EdgeInsets.zero) {
      content = SliverPadding(padding: padding, sliver: content);
    }
    return SliverSlotScope(
      enabled: true,
      scrollDirection: scrollDirection,
      child: LayoutSelectionScope(
        owner: this,
        path: [..._path, spec.label],
        child: Builder(
          key: _keys.putIfAbsent('$id:sliver', GlobalKey.new),
          builder: (regionContext) => EditorSelectionRegion(
            enabled: editing,
            isZone: true,
            selected: selected && _selectedSlot == null,
            onSelect: () => select(id, regionContext),
            child: EditorSlot(
              id: _effectiveComponentId,
              zoneId: id,
              label: spec.label,
              menuTitle: 'zone ${spec.label}',
              menuSubtitle: () => _componentLabel,
              menuTooltip: () => _regionTooltip(id),
              menuIcon: EditorSlot.zoneMenuIcon,
              menuDestination: spec.menuDestination,
              editable: true,
              scrollable: _isRegionScrollable(id),
              fixedHeight: sizeOf(id) != null,
              axisAction: spec.editableFlow ? () => _axisActionFor(id) : null,
              onEdit: widget.onEditRegion != null
                  ? () => EditorWizardNavigation.openWithTab(
                      EditorWizardTab.properties,
                      () => widget.onEditRegion!(id),
                      delegate: spec.editableFlow
                          ? _buildRegionFlowDelegate(id)
                          : null,
                    )
                  : () => configure(
                      regionId: id,
                      initialTab: EditorWizardTab.properties,
                    ),
              onAdd: () => add(id),
              wrapChildrenActions: wrapActionsForRegion(id),
              onContextMenu: (_) => select(id, regionContext),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  /// Construit la cible de dépôt ([SlotZoneTarget]) et les overlays de sélection,
  /// de survol et de badge d'une région [id] (partagé entre [regionOverlay] et [region]).
  Widget _buildRegionZoneTarget({
    required String id,
    required Key dropKey,
    required AlignmentGeometry alignment,
    required bool showBadge,
    required List<SlotImplementation> slots,
    required BuildContext? Function() targetContext,
    required Widget child,
    Widget? editingChild,
  }) {
    if (!editing) {
      return Stack(key: dropKey, alignment: alignment, children: [child]);
    }
    final spec = definition(id);
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
    final colors = Theme.of(context).colorScheme;
    return SlotZoneTarget(
      key: dropKey,
      owner: this,
      zoneLabel: spec.label,
      ids: _config.value.slotsOf(id),
      canMove: (slotId) => _canMoveSlot(slotId, id),
      onMove: (slotId) => _moveSlot(slotId, id),
      alignment: alignment,
      overlays: [
        if (overlay)
          Positioned.fill(
            child: EditorOverlayVisibility(
              child: selected
                  ? (_selectedSlot != null
                        ? EditorSelectionBorder.subtleParent(
                            key: ValueKey('${widget.keyPrefix}-selected-$id'),
                          )
                        : EditorSelectionBorder.active(
                            key: ValueKey('${widget.keyPrefix}-selected-$id'),
                          ))
                  : IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colors.outlineVariant,
                            width: 1,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        if (overlay && showBadge)
          ValueListenableBuilder<Set<Object>>(
            valueListenable: _hoveredRegionScopes,
            builder: (context, hoveredRegions, _) => hoveredRegions.contains(id)
                ? EditorZoneHighlight(
                    key: ValueKey('${widget.keyPrefix}-zone-highlight-$id'),
                  )
                : const SizedBox.shrink(),
          ),
        if (overlay && showBadge)
          Positioned.fill(
            key: ValueKey('${widget.keyPrefix}-badge-$id'),
            child: EditorOverlay(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: EmphasizedLabel(
                    emphasis: emphasis,
                    allScopes: true,
                    child: EditorZoneBadge(
                      key: ValueKey('${widget.keyPrefix}-badge-content-$id'),
                      label: spec.label,
                      labelKey: ValueKey('${widget.keyPrefix}-select-$id'),
                      selected: selected,
                      hasSelectedChild: selected && _selectedSlot != null,
                      onHover: (hovered) => emphasis.report(id, hovered),
                      onTap: () =>
                          select(selected ? null : id, targetContext()),
                      onAdd: slots.isEmpty
                          ? () {
                              select(id, targetContext());
                              add(id);
                            }
                          : null,
                      addKey: ValueKey('${widget.keyPrefix}-add-$id'),
                      addTooltip: 'Ajouter dans ${spec.label}',
                      actions: [
                        if (spec.editableFlow && selected) ...[
                          ZoneAxisButton(
                            key: ValueKey(
                              '${widget.keyPrefix}-toggle-axis-$id',
                            ),
                            action: _axisActionFor(id),
                            compact: true,
                            color: colors.onSurface,
                          ),
                          IconButton(
                            key: ValueKey('${widget.keyPrefix}-flow-$id'),
                            tooltip:
                                '${spec.label} : Taille et paramètres de flux',
                            visualDensity: VisualDensity.compact,
                            iconSize: 14,
                            padding: const EdgeInsets.all(2),
                            constraints: const BoxConstraints(),
                            color: colors.onSurface,
                            onPressed: () => _openRegionFlowEditor(id),
                            icon: const Icon(Icons.straighten),
                          ),
                        ],
                        ...?widget.regionActions?.call(id),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
      child: editingChild ?? child,
    );
  }

  /// Enveloppe un widget Box [child] (tel qu'un `CustomScrollView`) avec la cible de dépôt,
  /// la bordure de sélection, le surlignage de survol et le badge de la région [id].
  Widget regionOverlay(
    String id, {
    required Widget child,
    bool showBadge = true,
  }) {
    final spec = definition(id);
    final regionAxis = axisOf(id);
    final slots = slotsFor(id);
    final alignment = regionAxis == Axis.horizontal && !spec.stretch
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.topStart;
    final keyedChild = KeyedSubtree(
      key: _regionContentKeys.putIfAbsent('$id:overlay', GlobalKey.new),
      child: child,
    );
    return _buildRegionZoneTarget(
      id: id,
      dropKey: ValueKey('${widget.keyPrefix}-slot-drop-$id'),
      alignment: alignment,
      showBadge: showBadge,
      slots: slots,
      targetContext: () =>
          _keys['$id:sliver']?.currentContext ?? _keys[id]?.currentContext,
      child: keyedChild,
    );
  }

  /// Décore une région de propriété native sans modifier la composition de l'adaptateur.
  Widget region(
    String id, {
    Widget? child,
    SlotImplementation? item,
    bool showBadge = true,
    bool? expand,
    bool? stretch,
  }) {
    final spec = definition(id);
    final regionAxis = axisOf(id);
    final regionFlow = flowOf(id);
    final fixedSize = sizeOf(id);
    final effectiveExpand = expand ?? spec.expand;
    final effectiveStretch = stretch ?? spec.stretch;
    final slots = item == null ? slotsFor(id) : [item];
    final overlay = _showOverlay();
    final selected = _selected == id;
    final emphasis = LabelEmphasis(
      scopes: _hoveredRegionScopes,
      scope: id,
      onHover: (_, _, value) => _setRegionHovered(id, value),
    );
    Widget content =
        child ??
        SlotStack(
          slots: slots,
          focusKeys: _slotKeys,
          axis: regionAxis,
          flow: regionFlow,
          expand: fixedSize != null && regionAxis == Axis.vertical
              ? true
              : effectiveExpand,
          stretch: fixedSize != null && regionAxis == Axis.horizontal
              ? true
              : effectiveStretch,
          preferredSizes: {
            for (final slot in slots)
              if (slot case NativePreferredSizeWidget native)
                slot.id: native.preferredSizeIn(context),
            ...widget.config.slotPreferredSizes,
            if (spec.fillSize != null)
              for (final slot in slots)
                if (slot.sizing == SlotSizing.fill &&
                    slot.tags.intersection(const {
                      'action',
                      'button',
                      'text',
                    }).isEmpty &&
                    slot.preferredSize == null &&
                    !widget.config.slotPreferredSizes.containsKey(slot.id))
                  slot.id: spec.fillSize,
          },
          sizeConstraints: widget.config.slotSizeConstraints,
          layoutSize: _layoutSize,
          showLabels: overlay,
          zoneLabel: spec.label,
          selectedSlotId: selected ? _selectedSlot : null,
          onSelectSlot: editing && widget.editSurface
              ? (slot) => _toggleSlot(id, slot)
              : null,
          onSelectContent: editing ? (slot) => _selectSlot(id, slot) : null,
          canSelectSlot: _canSelectSlot,
          onResizeSlot: editing && widget.editSurface
              ? (slot, dimensions) => _update(
                  _config.value.withSlotSizeConstraints(slot.id, dimensions),
                )
              : null,
          mover: editing
              ? SlotMover(
                  owner: this,
                  canMove: (slotId) => _canMoveSlot(slotId, id),
                  onMove: (slotId, {beforeId, afterId}) => _moveSlot(
                    slotId,
                    id,
                    beforeId: beforeId,
                    afterId: afterId,
                  ),
                )
              : null,
          onRemoveSlot: editing
              ? (slot) async {
                  if (widget.onSlotRemoved != null) {
                    await widget.onSlotRemoved!(id, slot);
                    return;
                  }
                  removeSlotInstance(
                    context,
                    id: slot.id,
                    type: _config.value.slotTypeOf(slot.id),
                    containerKind: EditorConfigKind.nativeComponent,
                    unplace: () => _update(_config.value.withoutSlot(slot.id)),
                  );
                }
              : null,
          onEditPreferredSize: editing ? _editSize : null,
          dimensionDelegateForSlot: editing ? _buildSlotSizeDelegate : null,
          wrapActionsForSlot: editing
              ? (slot) => wrapActionsForSlot(id, slot)
              : null,
          insertionForSlot: editing
              ? (slot) => insertionForSlot(id, slot)
              : null,
          emphasis: emphasis,
        );
    if (fixedSize != null) {
      content = SizedBox(height: fixedSize, child: content);
    }
    final regionKey = item == null ? id : '$id:${item.id}';
    content = KeyedSubtree(
      key: _regionContentKeys.putIfAbsent(regionKey, GlobalKey.new),
      child: content,
    );
    final dropKey = ValueKey(
      '${widget.keyPrefix}-slot-drop-$id${item == null ? '' : ':${item.id}'}',
    );
    final alignment = regionAxis == Axis.horizontal && !effectiveStretch
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.topStart;
    return LayoutSelectionScope(
      owner: this,
      path: [..._path, spec.label],
      child: Builder(
        key: _keys.putIfAbsent(regionKey, GlobalKey.new),
        builder: (regionContext) => EditorSelectionRegion(
          enabled: editing,
          isZone: true,
          selected: selected && _selectedSlot == null,
          onSelect: () => select(id, regionContext),
          child: EditorSlot(
            id: _effectiveComponentId,
            zoneId: id,
            label: spec.label,
            menuTitle: 'zone ${spec.label}',
            menuSubtitle: () => _componentLabel,
            menuTooltip: () => _regionTooltip(id),
            menuIcon: EditorSlot.zoneMenuIcon,
            menuDestination: spec.menuDestination,
            editable: true,
            scrollable: _isRegionScrollable(id),
            fixedHeight: fixedSize != null,
            axisAction: spec.editableFlow ? () => _axisActionFor(id) : null,
            onEdit: widget.onEditRegion != null
                ? () => EditorWizardNavigation.openWithTab(
                    EditorWizardTab.properties,
                    () => widget.onEditRegion!(id),
                    delegate: spec.editableFlow
                        ? _buildRegionFlowDelegate(id)
                        : null,
                  )
                : () => configure(
                    regionId: id,
                    initialTab: EditorWizardTab.properties,
                  ),
            onAdd: () => add(id),
            wrapChildrenActions: wrapActionsForRegion(id),
            onContextMenu: (_) => select(id, regionContext),
            child: _buildRegionZoneTarget(
              id: id,
              dropKey: dropKey,
              alignment: alignment,
              showBadge: showBadge,
              slots: slots,
              targetContext: () => regionContext,
              child: content,
              editingChild: slots.isEmpty && editing
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final fillWidth =
                            (regionAxis == Axis.horizontal
                                ? effectiveExpand
                                : effectiveStretch) &&
                            constraints.hasBoundedWidth;
                        final fillHeight =
                            fixedSize == null &&
                            (regionAxis == Axis.vertical
                                ? effectiveExpand
                                : effectiveStretch) &&
                            constraints.hasBoundedHeight;
                        return SizedBox(
                          width: fillWidth
                              ? double.infinity
                              : (spec.emptySize.width.isFinite
                                    ? spec.emptySize.width
                                    : (constraints.hasBoundedWidth
                                          ? double.infinity
                                          : 120)),
                          height:
                              fixedSize ??
                              (fillHeight
                                  ? double.infinity
                                  : (spec.emptySize.height.isFinite
                                        ? spec.emptySize.height
                                        : kToolbarHeight)),
                        );
                      },
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
  }
}
