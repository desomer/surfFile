// Résolution du catalogue de slots (fournis ou issus du [Registry]),
// renommage d'instance et gestion des contraintes de taille de slots.
part of '../native_component_editor.dart';

/// Extension gérant la résolution des slots et leur dimensionnement dans [NativeComponentEditorState].
extension NativeComponentEditorSlots on NativeComponentEditorState {
  /// Calcule la taille préférée effective d'un [slot] en tenant compte des surcharges
  /// et contraintes persistées dans [NativeComponentConfig].
  Size? preferredSizeFor(SlotImplementation slot) {
    final base = widget.config.slotPreferredSizes.containsKey(slot.id)
        ? widget.config.slotPreferredSizes[slot.id]
        : switch (slot) {
            NativePreferredSizeWidget native => native.preferredSizeIn(context),
            _ => slot.preferredSize,
          };
    final configured = widget.config.slotSizeConstraints[slot.id];
    if (configured == null || !configured.hasSizeConstraints) {
      return base;
    }
    final media = MediaQuery.maybeSizeOf(context) ?? Size.zero;
    final basisWidth = _layoutSize.width > 0 ? _layoutSize.width : media.width;
    final basisHeight = _layoutSize.height > 0
        ? _layoutSize.height
        : media.height;
    double? resolveDimension(
      SlotDimension? preferred,
      SlotDimension? min,
      SlotDimension? max,
      double basis,
      double? fallback,
    ) {
      var value = preferred?.resolve(basis) ?? fallback;
      final minVal = min?.resolve(basis);
      final maxVal = max?.resolve(basis);
      if (value != null && value.isFinite) {
        if (minVal != null) value = math.max(value, minVal);
        if (maxVal != null) value = math.min(value, maxVal);
        return value;
      }
      if (minVal != null) {
        return maxVal != null ? math.min(minVal, maxVal) : minVal;
      }
      return value;
    }

    final width = resolveDimension(
      configured.preferredWidth,
      configured.minWidth,
      configured.maxWidth,
      basisWidth,
      base?.width,
    );
    final height = resolveDimension(
      configured.preferredHeight,
      configured.minHeight,
      configured.maxHeight,
      basisHeight,
      base?.height,
    );
    if (width == null && height == null) return base;
    return Size(width ?? double.infinity, height ?? double.infinity);
  }

  Map<String, SlotImplementation> _provided() {
    final result = <String, SlotImplementation>{};
    for (final slot in widget.slots) {
      if (result.containsKey(slot.id)) {
        throw StateError('Duplicate native slot ID: ${slot.id}');
      }
      result[slot.id] = slot;
    }
    return result;
  }

  String _componentType(String key, RegisteredComponent component) =>
      'component:${component.slotId ?? key}';

  Set<String> _tagsForType(String type, {String? id}) {
    final provided = _provided();
    final supplied =
        provided[id] ??
        provided[type] ??
        (id == null ? null : ProvidedSlotScope.find(context, id)) ??
        ProvidedSlotScope.find(context, type);
    if (supplied != null) return supplied.tags;
    final registry = widget.registry;
    if (registry == null) return const {};
    for (final entry in registry.components.entries) {
      if (type == _componentType(entry.key, entry.value) ||
          type == entry.value.slotId ||
          type == 'registry:${Uri.encodeComponent(entry.key)}') {
        return entry.value.tags;
      }
    }
    final key = type.startsWith('factory:')
        ? type.substring('factory:'.length)
        : type.startsWith('registry:')
        ? Uri.decodeComponent(type.substring('registry:'.length))
        : null;
    return registry.registry[key]?.tags ?? const {};
  }

  /// Retourne la liste ordonnée des [SlotImplementation] visibles placés dans [region].
  List<SlotImplementation> slotsFor(String region) {
    final provided = _provided();
    final result = <SlotImplementation>[];
    for (final id in widget.config.slotsOf(region)) {
      final type = widget.config.slotTypeOf(id);
      SlotImplementation? slot =
          provided[id] ??
          provided[type] ??
          ProvidedSlotScope.find(context, id) ??
          ProvidedSlotScope.find(context, type);
      final registry = widget.registry;
      if (slot == null && registry != null) {
        for (final entry in registry.components.entries) {
          if (type == _componentType(entry.key, entry.value) ||
              type == entry.value.slotId ||
              type == 'registry:${Uri.encodeComponent(entry.key)}') {
            if (!(entry.value.isAvailable?.call(context) ?? true)) {
              slot = BuilderSlot(
                id: id,
                label: entry.value.label,
                tags: entry.value.tags,
                menuIcon: entry.value.menuIcon,
                visible: false,
                builder: (_) => const SizedBox.shrink(),
              );
              break;
            }
            slot = entry.value.createSlot(id);
            break;
          }
        }
        if (slot == null &&
            (type.startsWith('factory:') || type.startsWith('registry:'))) {
          final factoryKey = type.startsWith('factory:')
              ? type.substring('factory:'.length)
              : Uri.decodeComponent(type.substring('registry:'.length));
          final factory = registry.registry[factoryKey];
          if (factory != null) {
            final child = factory.getWidget(XuiBuildCtx(id: id));
            slot = child is NativePreferredSizeWidget
                ? NativeWidgetSlot(
                    id: id,
                    label: factoryKey,
                    tags: factory.tags,
                    menuIcon: factory.menuIcon,
                    child: child,
                  )
                : BuilderSlot(
                    id: id,
                    label: factoryKey,
                    tags: factory.tags,
                    menuIcon: factory.menuIcon,
                    builder: (_) => child,
                  );
          }
        }
      }
      if (slot == null) {
        throw StateError(
          'Unresolved native slot "$id" (type "$type") in ${widget.label}.',
        );
      }
      if (slot.visible) {
        final source = slot;
        final SlotImplementation resolved;
        if (source.id == id) {
          resolved = source;
        } else if (source case NativePreferredSizeWidget native) {
          resolved = NativeWidgetSlot(
            id: id,
            label: source.label,
            tags: source.tags,
            menuIcon: source.menuIcon,
            child: native,
          );
        } else {
          resolved = BuilderSlot(
            id: id,
            label: source.label,
            sizing: source.sizing,
            preferredSize: source.preferredSize,
            showLabel: source.showLabel,
            labelAlignment: source.labelAlignment,
            tags: source.tags,
            menuIcon: source.menuIcon,
            builder: (_) => source,
          );
        }
        result.add(_named(resolved));
      }
    }
    return result;
  }

  /// Expose le nom d'instance de [slot] à son contenu, renommé via
  /// [NativeComponentConfig.slotLabels].
  SlotImplementation _named(SlotImplementation slot) {
    final id = slot.id;
    final previous = widget.config.slotLabels[id];
    void rename(String label) => _update(
      _config.value.withSlotLabel(id, label == slot.label ? null : label),
    );
    void restore() => _update(_config.value.withSlotLabel(id, previous));
    return slot is NativePreferredSizeWidget
        ? NativeInstanceSlot(
            slot,
            label: previous ?? slot.label,
            onRename: rename,
            onRestore: restore,
            overridden: previous != null,
          )
        : InstanceSlot(
            slot,
            label: previous ?? slot.label,
            onRename: rename,
            onRestore: restore,
            overridden: previous != null,
          );
  }

  ({Size layout, Rect zone, Rect slot})? _measureSlotBounds(
    SlotImplementation slot,
    NativeComponentConfig initial,
  ) {
    final layout = context.findRenderObject();
    final slotBox = _slotContext(slot.id)?.findRenderObject();
    final region = initial.placements.entries
        .where((entry) => entry.value.contains(slot.id))
        .firstOrNull
        ?.key;
    final zoneBox = _regionContext(region)?.findRenderObject();
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
  }

  void _applySlotDimensions(
    SlotImplementation slot,
    SlotSizeConstraints dimensions,
    bool useLegacyPixels,
  ) {
    if (useLegacyPixels &&
        dimensions.minWidth == null &&
        dimensions.minHeight == null &&
        dimensions.maxWidth == null &&
        dimensions.maxHeight == null &&
        !dimensions.hasPadding &&
        dimensions.preferredWidth?.unit == SlotSizeUnit.pixels &&
        dimensions.preferredHeight?.unit == SlotSizeUnit.pixels) {
      _update(
        _config.value.withSlotSize(
          slot.id,
          Size(
            dimensions.preferredWidth!.value,
            dimensions.preferredHeight!.value,
          ),
        ),
      );
    } else {
      _update(_config.value.withSlotSizeConstraints(slot.id, dimensions));
    }
  }

  SlotSizeDimensionDelegate _buildSlotSizeDelegate(SlotImplementation slot) {
    final initial = _config.value;
    return SlotSizeDimensionDelegate(
      context: context,
      slot: slot,
      saved: initial.slotSizeConstraints[slot.id],
      legacy: preferredSizeFor(slot),
      initialLabel: initial.slotLabels[slot.id] ?? slot.label,
      changes: _config,
      onLabelChanged: (label) => _update(
        _config.value.withSlotLabel(
          slot.id,
          label == slot.label ? null : label,
        ),
      ),
      measure: () => _measureSlotBounds(slot, initial),
      onApply: (dimensions, useLegacyPixels) =>
          _applySlotDimensions(slot, dimensions, useLegacyPixels),
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
              ..addAll({slot.id: ?initial.slotSizeConstraints[slot.id]}),
          ),
        );
      },
    );
  }

  Future<void> _editSize(SlotImplementation slot) async {
    final initial = _config.value;
    await showSlotSizeEditor(
      context: context,
      slot: slot,
      saved: initial.slotSizeConstraints[slot.id],
      legacy: preferredSizeFor(slot),
      changes: _config,
      target: _slotContext(slot.id),
      measure: () => _measureSlotBounds(slot, initial),
      onApply: (dimensions, useLegacyPixels) =>
          _applySlotDimensions(slot, dimensions, useLegacyPixels),
      onRestore: () {
        final current = _config.value;
        _update(
          current.copyWith(
            slotPreferredSizes: {...current.slotPreferredSizes}
              ..remove(slot.id)
              ..addAll({
                if (initial.slotPreferredSizes.containsKey(slot.id))
                  slot.id: initial.slotPreferredSizes[slot.id],
              }),
            slotSizeConstraints: {...current.slotSizeConstraints}
              ..remove(slot.id)
              ..addAll({slot.id: ?initial.slotSizeConstraints[slot.id]}),
          ),
        );
      },
    );
  }
}
