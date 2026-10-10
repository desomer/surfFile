part of '../super_layout.dart';

extension _SuperLayoutView on SuperLayoutState {
  Widget _buildLayout(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) {
      if ((StyleEditScope.controllerOf(context)?.value ?? false) &&
          event.buttons == kPrimaryButton) {
        _LayoutEditSelection.select(this, event);
      }
    },
    child: SuperContainer(
      decorate: false,
      label: widget.label,
      editable: widget.editable,
      onEdit: _openEditor,
      onAdd: () => _addSlot(_actionZone),
      axisAction: () => _axisAction(_actionZone),
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _config,
          _selected,
          _LayoutEditSelection.selected,
        ]),
        builder: (context, _) {
          final config = _config.value;
          // Seule la disposition selectionnee affiche ses actions overlay.
          final editMode =
              (StyleEditScope.controllerOf(context)?.value ?? false) &&
              identical(_LayoutEditSelection.selected.value, this);
          final parentPath = _LabelScope.pathOf(context);
          final selected = _selected.value;
          final name = widget.name ?? widget.label;
          LayoutSelection.register(this, [...parentPath, name], (zoneLabel) {
            if (!mounted) return;
            _selected.value = zoneLabel == null
                ? null
                : SuperLayoutZone.values
                      .where((zone) => zone.label == zoneLabel)
                      .firstOrNull;
            _LayoutEditSelection.selected.value = this;
          }, parent: this.context.findAncestorStateOfType<SuperLayoutState>());
          _reportPath(
            editMode
                ? [...parentPath, name, if (selected != null) selected.label]
                : const [],
            axis: editMode && widget.editable ? _axisAction(_actionZone) : null,
          );
          final editing = widget.showZoneNames && editMode;
          final zones = config.visibleZones;
          // Un côté automatique sans contenu garde sa taille fixe.
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
                children: [
                  for (final zone in zones)
                    _ZoneEntry(
                      key: ValueKey('super-layout-${zone.name}'),
                      zone: zone,
                      child: _LabelScope(
                        path: [...parentPath, name, zone.label],
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
                            axisAction: widget.editable
                                ? _axisAction(zone)
                                : null,
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
                          key: ValueKey(
                            'super-layout-add-overlay-${zone.name}',
                          ),
                          zone: zone,
                          overlay: true,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: IconButton.filled(
                                key: ValueKey('super-layout-add-${zone.name}'),
                                tooltip: 'Ajouter un slot dans ${zone.label}',
                                style: IconButton.styleFrom(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: .35),
                                  foregroundColor: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                                icon: const Icon(Icons.add),
                                onPressed: () => _addSlot(zone),
                              ),
                            ),
                          ),
                        ),
                  ],
                  if (widget.editable)
                    for (final side in SuperLayoutZone.values)
                      if (config.canResize(side) && zones.contains(side))
                        _ZoneEntry(
                          key: ValueKey(
                            'super-layout-resize-overlay-${side.name}',
                          ),
                          zone: side,
                          overlay: true,
                          resizeHandle: true,
                          child: _ZoneResizeHandle(
                            zone: side,
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
