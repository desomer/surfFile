part of 'super_layout.dart';

extension _SuperLayoutView on SuperLayoutState {
  Widget _buildLayout(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if ((StyleEditScope.controllerOf(context)?.value ?? false) &&
          event.buttons == kPrimaryButton) {
        _LayoutEditSelection.select(this, event);
      }
    },
    child: EditorSlot(
      label: _displayLabel,
      editable: widget.editable,
      onEdit: _openEditor,
      onAdd: () => _addSlot(_actionZone),
      menuIcon: widget.menuIcon,
      axisAction: _config.value.positioning == SuperLayoutPositioning.grid
          ? null
          : () => _axisAction(_actionZone),
      onContextMenu: _selectContextZone,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _config,
          _selected,
          _selectedSlot,
          _LayoutEditSelection.selected,
        ]),
        builder: (context, _) {
          final config = _config.value;
          if (config.positioning == SuperLayoutPositioning.grid) {
            return _buildGrid(context);
          }
          // Seule la disposition selectionnee affiche ses actions overlay.
          final styleEditMode =
              StyleEditScope.controllerOf(context)?.value ?? false;
          final editMode =
              styleEditMode &&
              identical(_LayoutEditSelection.selected.value, this);
          final parentPath = _LabelScope.pathOf(context);
          final selected = _selected.value;
          final selectedSlot = selected == null
              ? null
              : _slotsOf(
                  config,
                  config.contentZone(selected),
                ).where((slot) => slot.id == _selectedSlot.value).firstOrNull;
          final name =
              _config.value.label != null ||
                  (editorComponentLabelOf(context)?.overridden ?? false)
              ? _displayLabel
              : widget.name ?? widget.label;
          LayoutSelection.register(
            this,
            [...parentPath, name],
            (zoneLabel) {
              if (!mounted) return;
              _selectedSlot.value = null;
              _selected.value = zoneLabel == null
                  ? null
                  : SuperLayoutZone.values
                        .where((zone) => widget.zoneLabel(zone) == zoneLabel)
                        .firstOrNull;
              _LayoutEditSelection.activate(this);
            },
            parent:
                this.context.findAncestorStateOfType<SuperLayoutState>() ??
                LayoutSelectionScope.of(context)?.owner,
            selectSlot: (label) {
              final zone = _selected.value;
              if (!mounted || zone == null) return;
              final slots = _slotsOf(
                _config.value,
                _config.value.contentZone(zone),
              );
              final slot =
                  slots
                      .where(
                        (slot) =>
                            slot.id == selectedSlot?.id && slot.label == label,
                      )
                      .firstOrNull ??
                  slots.where((slot) => slot.label == label).firstOrNull;
              if (slot != null) _selectedSlot.value = slot.id;
            },
            onDeselect: () {
              if (!mounted) return;
              _selectedSlot.value = null;
              _selected.value = null;
              if (identical(_LayoutEditSelection.selected.value, this)) {
                _LayoutEditSelection.selected.value = null;
              }
            },
          );
          _reportPath(
            editMode
                ? [
                    ...parentPath,
                    name,
                    if (selected != null) widget.zoneLabel(selected),
                    if (selectedSlot != null) selectedSlot.label,
                  ]
                : const [],
            axis: editMode && widget.editable ? _axisAction(_actionZone) : null,
          );
          final editing = widget.showZoneNames && editMode;
          final zones = config.visibleZones;
          final emptyAutoSides = {
            if (!styleEditMode)
              for (final side in config.autoSides)
                if (zones.contains(side) &&
                    !_hasContent(config, config.contentZone(side)) &&
                    !zones.any(
                      (zone) =>
                          zone.isCorner &&
                          switch (side) {
                            SuperLayoutZone.north =>
                              zone == SuperLayoutZone.nw ||
                                  zone == SuperLayoutZone.ne,
                            SuperLayoutZone.south =>
                              zone == SuperLayoutZone.sw ||
                                  zone == SuperLayoutZone.se,
                            SuperLayoutZone.west =>
                              zone == SuperLayoutZone.nw ||
                                  zone == SuperLayoutZone.sw,
                            SuperLayoutZone.east =>
                              zone == SuperLayoutZone.ne ||
                                  zone == SuperLayoutZone.se,
                            _ => false,
                          } &&
                          _hasContent(config, config.contentZone(zone)),
                    ))
                  side,
          };
          final autoSides = {
            for (final side in config.autoSides)
              if (zones.contains(side) &&
                  !config.collapsedSides.containsKey(side) &&
                  _hasContent(config, config.contentZone(side)))
                side,
          };
          return LayoutBuilder(
            builder: (context, constraints) {
              final layoutSize = constraints.biggest;
              return _ZoneLayout(
                config: config,
                autoSides: autoSides,
                emptyAutoSides: emptyAutoSides,
                children: [
                  for (final zone in zones)
                    _ZoneEntry(
                      key: ValueKey('super-layout-${zone.name}'),
                      zone: zone,
                      child: KeyedSubtree(
                        key: _zoneFocusKeys.putIfAbsent(zone, GlobalKey.new),
                        child: _LabelScope(
                          path: [...parentPath, name, widget.zoneLabel(zone)],
                          child: Offstage(
                            offstage:
                                config.collapsedSides.containsKey(zone) ||
                                switch (zone) {
                                  SuperLayoutZone.nw =>
                                    config.collapsedSides.containsKey(
                                          SuperLayoutZone.north,
                                        ) ||
                                        config.collapsedSides.containsKey(
                                          SuperLayoutZone.west,
                                        ),
                                  SuperLayoutZone.ne =>
                                    config.collapsedSides.containsKey(
                                          SuperLayoutZone.north,
                                        ) ||
                                        config.collapsedSides.containsKey(
                                          SuperLayoutZone.east,
                                        ),
                                  SuperLayoutZone.sw =>
                                    config.collapsedSides.containsKey(
                                          SuperLayoutZone.south,
                                        ) ||
                                        config.collapsedSides.containsKey(
                                          SuperLayoutZone.west,
                                        ),
                                  SuperLayoutZone.se =>
                                    config.collapsedSides.containsKey(
                                          SuperLayoutZone.south,
                                        ) ||
                                        config.collapsedSides.containsKey(
                                          SuperLayoutZone.east,
                                        ),
                                  _ => false,
                                },
                            child: _contentOf(
                              config,
                              zone,
                              autoSides,
                              editMode,
                              layoutSize,
                            ),
                          ),
                        ),
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
                        child: SlotZoneTarget(
                          owner: this,
                          canMove: (id) => _canMoveSlot(id, zone),
                          zoneLabel: widget.zoneLabel(zone),
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
                            _canSwapZone(zone),
                        onSwap: (zone) => _update(config.withSwap(zone)),
                      ),
                    ),
                    for (final zone in zones)
                      _ZoneEntry(
                        key: ValueKey(
                          _hasContent(config, config.contentZone(zone))
                              ? 'super-layout-name-${zone.name}'
                              : 'super-layout-add-overlay-${zone.name}',
                        ),
                        zone: zone,
                        overlay: true,
                        child: EditorOverlay(
                          child: _ZoneNameBadge(
                            zone: zone,
                            label: widget.zoneLabel(zone),
                            zoneLabel: widget.zoneLabel,
                            axisAction: widget.editable
                                ? _axisAction(zone)
                                : null,
                            overCenter: _overCenter,
                            onCenterHint: (active) => _hintCenter(zone, active),
                            emphasis: _emphasisFor(zone),
                            selected: selected == zone,
                            onSelect: () => _select(zone),
                            onAdd: widget.editable
                                ? () => _addSlot(zone)
                                : null,
                            swapTarget: widget.editable && _canSwapZone(zone)
                                ? zone.opposite
                                : null,
                            moves: !zones.contains(zone.opposite),
                            onSwap: () => _update(config.withSwap(zone)),
                          ),
                        ),
                      ),
                  ],
                  if (widget.editable)
                    for (final side in SuperLayoutZone.values)
                      if (config.canResize(side) &&
                          zones.contains(side) &&
                          !emptyAutoSides.contains(side))
                        _ZoneEntry(
                          key: ValueKey(
                            'super-layout-resize-overlay-${side.name}',
                          ),
                          zone: side,
                          overlay: true,
                          resizeHandle: true,
                          child: _ZoneResizeHandle(
                            zone: side,
                            label: widget.zoneLabel(side),
                            restoreSize: config.collapsedSides[side],
                            onCollapse: (extent) => _update(
                              _config.value.copyWith(
                                collapsedSides: {
                                  ..._config.value.collapsedSides,
                                  side: extent.clamp(
                                    SuperLayoutConfig.minSize,
                                    SuperLayoutConfig.maxSize,
                                  ),
                                },
                              ),
                            ),
                            bounds: (size) => _config.value.resizeBounds(
                              side,
                              _slotsOf(
                                _config.value,
                                _config.value.contentZone(side),
                              ).map((slot) => slot.id),
                              side == SuperLayoutZone.north ||
                                      side == SuperLayoutZone.south
                                  ? size.height
                                  : size.width,
                            ),
                            onResize: (extent) {
                              if (!mounted || !widget.editable) return;
                              final current = _config.value;
                              if (!current.canResize(side) ||
                                  !current.hasSide(side)) {
                                return;
                              }
                              _update(
                                current
                                    .copyWith(
                                      collapsedSides: {
                                        ...current.collapsedSides,
                                      }..remove(side),
                                    )
                                    .withAuto(side, false)
                                    .withSize(side, extent),
                              );
                            },
                          ),
                        ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}
