// Gestion de la sélection dans l'arbre d'édition ([LayoutSelection]),
// des actions d'axe de région et du formatage des infobulles pour [NativeComponentEditorState].
part of '../native_component_editor.dart';

/// Extension gérant la sélection des régions/slots et les infobulles d'un [NativeComponentEditorState].
extension NativeComponentEditorSelection on NativeComponentEditorState {
  void _registerLayoutSelection(LayoutSelectionScope? scope) {
    LayoutSelection.register(
      this,
      _path,
      (targetLabel) {
        if (!widget.showRegionInPath) {
          if (targetLabel == null) {
            select(null);
            return;
          }
          final region = widget.regions.first.id;
          final slots = slotsFor(region);
          final slot = slots
              .where((s) => _resolvedSlotLabel(s) == targetLabel)
              .firstOrNull;
          if (slot != null) {
            selectSlot(region, slot);
          } else {
            select(null);
          }
          return;
        }
        select(
          widget.regions
              .where((region) => region.label == targetLabel)
              .firstOrNull
              ?.id,
        );
      },
      id: _effectiveComponentId,
      parent: scope?.owner,
      delegateToParent: !widget.showRegionInPath && scope != null,
      selectedSlotId: () => _selectedSlot,
      selectSlot: widget.showRegionInPath
          ? (slotLabel) {
              final region = _selected;
              if (!mounted || region == null) return;
              final slots = slotsFor(region);
              final slot =
                  slots
                      .where(
                        (s) =>
                            s.id == _selectedSlot &&
                            _resolvedSlotLabel(s) == slotLabel,
                      )
                      .firstOrNull ??
                  slots
                      .where((s) => _resolvedSlotLabel(s) == slotLabel)
                      .firstOrNull;
              if (slot != null) selectSlot(region, slot);
            }
          : null,
      onDeselect: _clear,
      onContextMenu: (position) => EditorSlotState.openMenuFromContext(
        !widget.editSurface && widget.showRegionInPath
            ? (_regionContext(_selected) ?? _regionContext('body') ?? context)
            : context,
        position,
      ),
      targetContext: () => !widget.editSurface && widget.showRegionInPath
          ? (_regionContext(_selected) ?? _regionContext('body') ?? context)
          : context,
      treeBuilder: () {
        if (!widget.showRegionInPath) {
          final regionId = widget.regions.first.id;
          final currentSlots = slotsFor(regionId);
          return [
            for (final slot in currentSlots)
              if (_canSelectSlot(slot))
                () {
                  final sLabel = _resolvedSlotLabel(slot);
                  final slotPath = [..._path, sLabel];
                  void selectThisSlot() => selectSlot(regionId, slot);
                  final slotCtx =
                      widget.slotContextFor?.call(slot) ??
                      _slotContext(slot.id, regionId) ??
                      _regionContext(regionId);
                  return LayoutSelectionNode(
                    id: _resolvedSlotId(slot, slotCtx),
                    label: sLabel,
                    path: slotPath,
                    icon: slot.menuIcon,
                    onSelect: selectThisSlot,
                    onContextMenu: (position) =>
                        EditorSlotState.openMenuFromContext(slotCtx, position),
                    targetContext: () =>
                        widget.slotContextFor?.call(slot) ??
                        _slotContext(slot.id, regionId) ??
                        _regionContext(regionId),
                    children: LayoutSelection.childrenFromContext(
                      slotCtx,
                      slotPath,
                      selectThisSlot,
                      ignoreOwner: this,
                    ),
                  );
                }(),
          ];
        }
        return [
          for (final region in widget.regions)
            if (visible(region.id))
              () {
                final regionPath = [..._path, region.label];
                final currentSlots = slotsFor(region.id);
                final slotNodes = <LayoutSelectionNode>[];
                for (final slot in currentSlots) {
                  final slotCtx =
                      widget.slotContextFor?.call(slot) ??
                      _slotContext(slot.id, region.id);
                  if (_canSelectSlot(slot)) {
                    final sLabel = _resolvedSlotLabel(slot);
                    final slotPath = [...regionPath, sLabel];
                    void selectThisSlot() => selectSlot(region.id, slot);
                    slotNodes.add(
                      LayoutSelectionNode(
                        id: _resolvedSlotId(slot, slotCtx),
                        label: sLabel,
                        path: slotPath,
                        icon: slot.menuIcon,
                        onSelect: selectThisSlot,
                        onContextMenu: (position) =>
                            EditorSlotState.openMenuFromContext(
                              slotCtx,
                              position,
                            ),
                        targetContext: () =>
                            widget.slotContextFor?.call(slot) ??
                            _slotContext(slot.id, region.id),
                        children: LayoutSelection.childrenFromContext(
                          slotCtx,
                          slotPath,
                          selectThisSlot,
                          ignoreOwner: this,
                        ),
                      ),
                    );
                  } else {
                    slotNodes.addAll(
                      LayoutSelection.childrenFromContext(
                        slotCtx ?? _regionContext(region.id),
                        regionPath,
                        () => select(region.id),
                        ignoreOwner: this,
                      ),
                    );
                  }
                }
                return LayoutSelectionNode(
                  id: 'region:${region.id}',
                  label: region.label,
                  path: regionPath,
                  icon: EditorSlot.zoneMenuIcon,
                  onSelect: () => select(region.id),
                  onContextMenu: (position) =>
                      EditorSlotState.openMenuFromContext(
                        _regionContext(region.id),
                        position,
                      ),
                  targetContext: () => _regionContext(region.id),
                  children: slotNodes,
                );
              }(),
        ];
      },
    );
  }

  void _editingChanged() {
    if (editing &&
        widget.showRegionInPath &&
        LayoutSelectionScope.of(context) == null) {
      select(null);
    } else {
      _clear();
    }
  }

  void _clear() {
    if (!mounted) return;
    _setEditorState(() {
      _active = false;
      _selected = null;
      _selectedSlot = null;
      _hoveredRegionScopes.value = {};
    });
    LayoutSelection.report(this, const []);
  }

  /// Sélectionne la région [id] (ou la surface complète si [id] est `null`).
  void select(String? id, [BuildContext? target]) {
    if (!mounted) return;
    LayoutSelection.activate(this);
    _setEditorState(() {
      _active = true;
      _selected = id;
      _selectedSlot = null;
    });
    widget.onRegionSelected?.call(id);
    LayoutSelection.report(
      this,
      [
        ..._path,
        if (id != null && widget.showRegionInPath) definition(id).label,
      ],
      axis: id != null && definition(id).editableFlow
          ? _axisActionFor(id)
          : null,
      clear: _clear,
      focusContext: target ?? _regionContext(id) ?? context,
    );
  }

  bool _isRegionScrollable(String id) {
    if (flowOf(id).scrollable) return true;
    if (id == 'body') {
      final bodyMode = _config.value.stringProperty('bodyMode');
      if (bodyMode != null && bodyMode != 'standard') return true;
    }
    return false;
  }

  LayoutAxisAction _axisActionFor(String id) {
    final spec = definition(id);
    final currentAxis = axisOf(id);
    final fixedSize = sizeOf(id);
    final defaultSize = spec.emptySize.height.isFinite
        ? spec.emptySize.height
        : 100.0;
    final hasNaturalHeight = currentAxis == Axis.vertical
        ? !spec.expand
        : !spec.stretch;
    return LayoutAxisAction(
      zoneLabel: spec.label,
      axis: currentAxis,
      scrollable: _isRegionScrollable(id),
      fixedHeight: fixedSize != null,
      onToggle: () {
        select(id);
        _update(
          _config.value.withRegionAxis(
            id,
            currentAxis == Axis.horizontal ? Axis.vertical : Axis.horizontal,
            defaultAxis: spec.axis,
          ),
        );
      },
      onEditFlow: () => _openRegionFlowEditor(id),
      flowTooltip: formatZoneFlowTooltip(
        zoneLabel: spec.label,
        axis: currentAxis,
        flow: flowOf(id),
        isSide: true,
        sizeAxis: hasNaturalHeight ? Axis.vertical : null,
        autoSize: fixedSize == null,
        size: fixedSize ?? defaultSize,
      ),
    );
  }

  String _componentTooltip() {
    final config = _config.value;
    if (widget.menuTooltip?.call(config) case final custom?) return custom;
    return formatNativeComponentTooltip(
      title: _componentLabel,
      config: config,
      regions: [
        for (final region in widget.regions)
          if (widget.isRegionAvailable?.call(config, region.id) ?? true)
            (
              label: region.label,
              count: slotsFor(region.id).length,
              enabled: enabled(region.id),
            ),
      ],
      propertyDescriptors: [
        for (final descriptor in widget.propertyDescriptors)
          if (widget.isPropertyAvailable?.call(config, descriptor) ?? true)
            descriptor,
      ],
    );
  }

  String _regionTooltip(String id) {
    final config = _config.value;
    if (widget.regionTooltip?.call(config, id) case final custom?) {
      return custom;
    }
    final spec = definition(id);
    final zoneSummary = spec.editableFlow
        ? _axisActionFor(id).flowTooltip!
        : [
            'Zone ${spec.label} ($_componentLabel)',
            [
              'Direction : ${axisOf(id) == Axis.horizontal ? 'Ligne (Row)' : 'Colonne (Column)'}',
              if (spec.single) 'Élément unique',
            ].join(' · '),
            'Éléments : ${slotsFor(id).length}',
          ].join('\n');
    if (!widget.editSurface && widget.onEditRegion == null) {
      final parentLines = _componentTooltip().split('\n').skip(1);
      if (parentLines.isNotEmpty) {
        return [zoneSummary, ...parentLines].join('\n');
      }
    }
    return zoneSummary;
  }

  /// Sélectionne un [slot] spécifique au sein de la [region].
  void selectSlot(
    String region,
    SlotImplementation slot, [
    BuildContext? target,
  ]) {
    if (!mounted) return;
    if (!_canSelectSlot(slot)) {
      if (widget.showRegionInPath) select(region, target);
      return;
    }
    LayoutSelection.activate(this);
    _setEditorState(() {
      _active = true;
      _selected = region;
      _selectedSlot = slot.id;
    });
    widget.onRegionSelected?.call(region);
    final customSlotCtx = widget.slotContextFor?.call(slot);
    final resolvedCustomCtx = customSlotCtx == null
        ? null
        : (EditorSlotState.resolveFromContext(customSlotCtx)?.context ??
              customSlotCtx);
    LayoutSelection.report(
      this,
      [
        ..._path,
        if (widget.showRegionInPath) definition(region).label,
        _resolvedSlotLabel(slot),
      ],
      clear: _clear,
      focusContext:
          target ??
          resolvedCustomCtx ??
          _slotContext(slot.id, region) ??
          _regionContext(region) ??
          context,
    );
  }

  void _toggleSlot(String region, SlotImplementation slot) {
    if (_active && _selected == region && _selectedSlot == slot.id) {
      select(region);
    } else {
      selectSlot(region, slot);
    }
  }

  void _selectSlot(String region, SlotImplementation slot) {
    selectSlot(region, slot);
  }
}
