part of 'super_layout.dart';

extension _SuperLayoutSlotSizeEditor on SuperLayoutState {
  SlotSizeDimensionDelegate _buildSlotSizeDelegate(
    SlotImplementation slot, {
    SuperLayoutConfig? initialOverride,
  }) {
    final initial = initialOverride ?? _config.value;
    final saved = initial.slotSizeConstraints[slot.id];
    return SlotSizeDimensionDelegate(
      context: context,
      slot: slot,
      saved: saved,
      legacy: initial.slotPreferredSizes.containsKey(slot.id)
          ? initial.slotPreferredSizes[slot.id]
          : slot.preferredSize,
      initialLabel: initial.slotLabels[slot.id] ?? slot.label,
      changes: _config,
      onLabelChanged: (label) =>
          _update(_config.value.withSlotLabel(slot.id, label)),
      measure: () {
        final layout = context.findRenderObject();
        final cellBox = _slotFocusKeys[slot.id]?.currentContext
            ?.findRenderObject();
        final slotBox = _config.value.positioning == SuperLayoutPositioning.grid
            ? _gridSlotSizeKeys[slot.id]?.currentContext?.findRenderObject()
            : cellBox;
        final zone = _displayZoneOf(_config.value, slot.id);
        final zoneBox = _config.value.positioning == SuperLayoutPositioning.grid
            ? cellBox
            : _zoneFocusKeys[zone]?.currentContext?.findRenderObject();
        if (layout is! RenderBox ||
            !layout.hasSize ||
            slotBox is! RenderBox ||
            !slotBox.hasSize ||
            zoneBox is! RenderBox ||
            !zoneBox.hasSize) {
          return null;
        }
        Rect bounds(RenderBox box) => MatrixUtils.transformRect(
          box.getTransformTo(layout),
          Offset.zero & box.size,
        );
        return (
          layout: layout.size,
          zone: bounds(zoneBox),
          slot: bounds(slotBox),
        );
      },
      onApply: (dimensions, useLegacyPixels) => _applySlotDimensions(
        slot,
        dimensions,
        useLegacyPixels: useLegacyPixels,
      ),
      onRestore: () {
        final current = _config.value;
        _update(
          current.copyWith(
            slotLabels: {...current.slotLabels}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotLabels.containsKey(slot.id))
                  slot.id: initial.slotLabels[slot.id]!,
              }),
            slotPreferredSizes: {...current.slotPreferredSizes}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotPreferredSizes.containsKey(slot.id))
                  slot.id: initial.slotPreferredSizes[slot.id],
              }),
            slotSizeConstraints: {...current.slotSizeConstraints}
              ..remove(slot.id)
              ..addAll({slot.id: ?saved}),
          ),
        );
      },
    );
  }

  Future<void> _editSlotPreferredSize(SlotImplementation slot) async {
    final initial = _config.value;
    final saved = initial.slotSizeConstraints[slot.id];
    await showSlotSizeEditor(
      context: context,
      slot: slot,
      saved: saved,
      legacy: initial.slotPreferredSizes.containsKey(slot.id)
          ? initial.slotPreferredSizes[slot.id]
          : slot.preferredSize,
      initialLabel: initial.slotLabels[slot.id] ?? slot.label,
      changes: _config,
      target: _slotFocusKeys[slot.id]?.currentContext,
      onLabelChanged: (label) =>
          _update(_config.value.withSlotLabel(slot.id, label)),
      measure: () {
        final layout = context.findRenderObject();
        final cellBox = _slotFocusKeys[slot.id]?.currentContext
            ?.findRenderObject();
        final slotBox = _config.value.positioning == SuperLayoutPositioning.grid
            ? _gridSlotSizeKeys[slot.id]?.currentContext?.findRenderObject()
            : cellBox;
        final zone = _displayZoneOf(_config.value, slot.id);
        final zoneBox = _config.value.positioning == SuperLayoutPositioning.grid
            ? cellBox
            : _zoneFocusKeys[zone]?.currentContext?.findRenderObject();
        if (layout is! RenderBox ||
            !layout.hasSize ||
            slotBox is! RenderBox ||
            !slotBox.hasSize ||
            zoneBox is! RenderBox ||
            !zoneBox.hasSize) {
          return null;
        }
        Rect bounds(RenderBox box) => MatrixUtils.transformRect(
          box.getTransformTo(layout),
          Offset.zero & box.size,
        );
        return (
          layout: layout.size,
          zone: bounds(zoneBox),
          slot: bounds(slotBox),
        );
      },
      onApply: (dimensions, useLegacyPixels) => _applySlotDimensions(
        slot,
        dimensions,
        useLegacyPixels: useLegacyPixels,
      ),
      onRestore: () {
        final current = _config.value;
        _update(
          current.copyWith(
            slotLabels: {...current.slotLabels}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotLabels.containsKey(slot.id))
                  slot.id: initial.slotLabels[slot.id]!,
              }),
            slotPreferredSizes: {...current.slotPreferredSizes}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotPreferredSizes.containsKey(slot.id))
                  slot.id: initial.slotPreferredSizes[slot.id],
              }),
            slotSizeConstraints: {...current.slotSizeConstraints}
              ..remove(slot.id)
              ..addAll({slot.id: ?saved}),
          ),
        );
      },
    );
  }

  void _applySlotDimensions(
    SlotImplementation slot,
    SlotSizeConstraints result, {
    bool useLegacyPixels = false,
  }) {
    final current = _config.value;
    if (result.minWidth == null &&
        result.minHeight == null &&
        result.maxWidth == null &&
        result.maxHeight == null &&
        result.preferredWidth == null &&
        result.preferredHeight == null &&
        !result.hasPadding &&
        result.fitContent == null) {
      _update(
        current
            .withSlotPreferredSize(slot.id, null)
            .copyWith(
              slotSizeConstraints: {...current.slotSizeConstraints}
                ..remove(slot.id),
            ),
      );
    } else if (result.minWidth == null &&
        result.minHeight == null &&
        result.maxWidth == null &&
        result.maxHeight == null &&
        !result.hasPadding &&
        result.fitContent == null &&
        (useLegacyPixels ||
            (result.percentBasis == SlotPercentBasis.zone &&
                current.slotSizeConstraints[slot.id] == null)) &&
        result.preferredWidth?.unit == SlotSizeUnit.pixels &&
        result.preferredHeight?.unit == SlotSizeUnit.pixels &&
        result.preferredWidth!.value > 0 &&
        result.preferredHeight!.value > 0) {
      _update(
        current
            .withSlotPreferredSize(
              slot.id,
              Size(result.preferredWidth!.value, result.preferredHeight!.value),
            )
            .copyWith(
              slotSizeConstraints: {...current.slotSizeConstraints}
                ..remove(slot.id),
            ),
      );
    } else {
      _update(
        current.copyWith(
          slotPreferredSizes: {...current.slotPreferredSizes}..remove(slot.id),
          slotSizeConstraints: {
            ...current.slotSizeConstraints,
            slot.id: result,
          },
        ),
      );
    }
  }
}
