// Déplacement de slots par glisser-déposer et actions d'encapsulation (`wrap`)
// au niveau d'un slot ou d'une région pour [NativeComponentEditorState].
part of '../native_component_editor.dart';

/// Extension gérant le déplacement et l'encapsulation des slots d'un [NativeComponentEditorState].
extension NativeComponentEditorInteractions on NativeComponentEditorState {
  bool _canMoveSlot(String slotId, String region) {
    if (!editing || !enabled(region)) return false;
    final config = _config.value;
    if (!config.placements.values.any((ids) => ids.contains(slotId))) {
      return false;
    }
    final current = config.slotsOf(region);
    if (definition(region).single && current.any((id) => id != slotId)) {
      return false;
    }
    return current.contains(slotId) ||
        definition(region).tagFilter
            .accepts(_tagsForType(config.slotTypeOf(slotId), id: slotId));
  }

  void _moveSlot(
    String slotId,
    String region, {
    String? beforeId,
    String? afterId,
  }) {
    if (!_canMoveSlot(slotId, region)) {
      final message =
          'Déplacement impossible vers ${definition(region).label} : '
          'zone indisponible, occupée ou composant incompatible.';
      debugPrint(message);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final next = _config.value.withSlotMoved(
      slotId,
      region,
      beforeId: beforeId,
      afterId: afterId,
    );
    if (identical(next, _config.value)) return;
    _update(next);
    if (mounted && identical(_config.value, next)) select(region);
  }

  /// Choix d'encapsulation acceptés par la région native [region] pour [slot].
  List<EditorSlotWrapAction> wrapActionsForSlot(
    String region,
    SlotImplementation slot,
  ) => slotWrapActions(
    registry: widget.registry,
    acceptsTags: definition(region).tagFilter.accepts,
    onWrap: (wrapper) async {
      if (!mounted || !_config.value.slotsOf(region).contains(slot.id)) return;
      final current = _config.value;
      wrapSlotInstance(
        context,
        registry: widget.registry!,
        wrapper: wrapper,
        id: slot.id,
        type: current.slotTypeOf(slot.id),
        label: slot.label,
        occupiedIds: {
          for (final ids in current.placements.values) ...ids,
          ...widget.slots.map((s) => s.id),
        },
        replace: (id, type) {
          var next = current.withSlotReplaced(slot.id, id, type);
          final preferred = preferredSizeFor(slot);
          if (!current.slotPreferredSizes.containsKey(slot.id) &&
              !current.slotSizeConstraints.containsKey(slot.id) &&
              preferred != null) {
            next = next.withSlotSize(id, preferred);
          }
          _update(next);
          _selectedSlot = id;
        },
      );
    },
  );

  /// Choix d'encapsulation de l'ensemble des enfants de la [region].
  List<EditorSlotWrapAction> wrapActionsForRegion(String region) {
    final children = slotsFor(region);
    return zoneChildrenWrapActions(
      registry: widget.registry,
      hasChildren: children.isNotEmpty,
      acceptsTags: definition(region).tagFilter.accepts,
      onWrapInCard: () async {
        if (!mounted) return;
        final current = _config.value;
        final slots = slotsFor(region);
        if (slots.isEmpty || widget.registry == null) return;
        final childIds = [for (final slot in slots) slot.id];
        final movedSet = childIds.toSet();
        wrapZoneChildrenInCard(
          context,
          registry: widget.registry!,
          childIds: childIds,
          slotTypes: {for (final id in childIds) id: current.slotTypeOf(id)},
          slotLabels: {
            for (final slot in slots)
              slot.id: current.slotLabels[slot.id] ?? slot.label,
          },
          slotPreferredSizes: {
            for (final slot in slots)
              if (current.slotPreferredSizes.containsKey(slot.id))
                slot.id: current.slotPreferredSizes[slot.id]
              else if (!current.slotSizeConstraints.containsKey(slot.id) &&
                  preferredSizeFor(slot) != null)
                slot.id: preferredSizeFor(slot),
          },
          slotSizeConstraints: {
            for (final id in childIds) id: ?current.slotSizeConstraints[id],
          },
          axis: axisOf(region),
          flow: flowOf(region),
          occupiedIds: {
            for (final ids in current.placements.values) ...ids,
            ...widget.slots.map((s) => s.id),
          },
          replaceChildren: (cardId, cardType) {
            final stillReferenced = <String>{
              for (final entry in current.placements.entries)
                if (entry.key != region) ...entry.value,
            };
            final removedOnly = movedSet.difference(stillReferenced);
            final next = current.copyWith(
              placements: {
                ...current.placements,
                region: [cardId],
              },
              slotTypes: {
                for (final entry in current.slotTypes.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
                cardId: cardType,
              },
              slotPreferredSizes: {
                for (final entry in current.slotPreferredSizes.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
              },
              slotSizeConstraints: {
                for (final entry in current.slotSizeConstraints.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
              },
              slotLabels: {
                for (final entry in current.slotLabels.entries)
                  if (!removedOnly.contains(entry.key)) entry.key: entry.value,
              },
            );
            _update(next);
            _selectedSlot = cardId;
          },
        );
      },
    );
  }
}
