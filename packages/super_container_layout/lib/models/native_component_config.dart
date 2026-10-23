import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;

import 'json_syntax.dart';
import 'super_layout_config.dart' show SlotSizeConstraints;

/// Immutable placements shared by adapters for native Flutter components.
class NativeComponentConfig {
  NativeComponentConfig({
    this.useDefaultNavigation,
    Map<String, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<String, bool> regions = const {},
    Map<String, Size?> slotPreferredSizes = const {},
    Map<String, SlotSizeConstraints> slotSizeConstraints = const {},
    Map<String, String> slotLabels = const {},
  }) : placements = Map.unmodifiable({
         for (final entry in placements.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       slotTypes = Map.unmodifiable(slotTypes),
       regions = Map.unmodifiable(regions),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = Map.unmodifiable({
         for (final entry in slotLabels.entries)
           if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
       }) {
    final ids = placements.values.expand((value) => value).toList();
    if (ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length ||
        placements.keys.any((id) => id.trim().isEmpty) ||
        regions.keys.any((id) => id.trim().isEmpty) ||
        slotTypes.keys.any((id) => id.trim().isEmpty) ||
        slotTypes.values.any((type) => type.trim().isEmpty) ||
        slotPreferredSizes.keys.any((id) => id.trim().isEmpty) ||
        slotSizeConstraints.keys.any((id) => id.trim().isEmpty) ||
        slotLabels.keys.any((id) => id.trim().isEmpty) ||
        slotPreferredSizes.values.any(
          (size) =>
              size != null &&
              (size.width.isNaN ||
                  size.height.isNaN ||
                  size.width < 0 ||
                  size.height < 0),
        )) {
      throw ArgumentError('Region and slot IDs must be unique and non-empty.');
    }
  }

  final Map<String, List<String>> placements;

  /// Null preserves the adapter's automatic navigation policy.
  final bool? useDefaultNavigation;
  final Map<String, String> slotTypes;
  final Map<String, bool> regions;
  final Map<String, Size?> slotPreferredSizes;
  final Map<String, SlotSizeConstraints> slotSizeConstraints;

  /// Display names given to slot instances; a technical ID never changes.
  final Map<String, String> slotLabels;

  bool isEnabled(String region) =>
      regions[region] ?? slotsOf(region).isNotEmpty;
  List<String> slotsOf(String region) => placements[region] ?? const [];
  String slotTypeOf(String id) => slotTypes[id] ?? id;

  /// Replaces a placement in place, keeping its outer sizing.
  NativeComponentConfig withSlotReplaced(
    String id,
    String replacementId,
    String type,
  ) {
    if (!placements.values.any((ids) => ids.contains(id)) ||
        replacementId.trim().isEmpty ||
        placements.values.any((ids) => ids.contains(replacementId))) {
      throw ArgumentError('Invalid slot replacement.');
    }
    return NativeComponentConfig(
      useDefaultNavigation: useDefaultNavigation,
      placements: {
        for (final entry in placements.entries)
          entry.key: [
            for (final slot in entry.value) slot == id ? replacementId : slot,
          ],
      },
      slotTypes: {...slotTypes}
        ..remove(id)
        ..[replacementId] = type,
      regions: regions,
      slotPreferredSizes: {
        for (final entry in slotPreferredSizes.entries)
          (entry.key == id ? replacementId : entry.key): entry.value,
      },
      slotSizeConstraints: {
        for (final entry in slotSizeConstraints.entries)
          (entry.key == id ? replacementId : entry.key): entry.value,
      },
      slotLabels: {...slotLabels}..remove(id),
    );
  }

  NativeComponentConfig withDefaultNavigation(bool enabled) =>
      NativeComponentConfig(
        useDefaultNavigation: enabled,
        placements: placements,
        slotTypes: slotTypes,
        regions: regions,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
      );

  NativeComponentConfig withRegionEnabled(String region, bool enabled) =>
      NativeComponentConfig(
        useDefaultNavigation: useDefaultNavigation,
        placements: placements,
        slotTypes: slotTypes,
        regions: {...regions, region: enabled},
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
      );

  NativeComponentConfig withSlotAdded(
    String id,
    String region, {
    String? type,
    bool replace = false,
  }) {
    final next = {
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    };
    final replaced = replace ? next.remove(region) ?? <String>[] : <String>[];
    next.putIfAbsent(region, () => []).add(id);
    final types = {...slotTypes}
      ..removeWhere((key, _) => key == id || replaced.contains(key));
    if (type != null && type != id) types[id] = type;
    return NativeComponentConfig(
      useDefaultNavigation: useDefaultNavigation,
      placements: next,
      slotTypes: types,
      regions: {...regions, region: true},
      slotPreferredSizes: {...slotPreferredSizes}
        ..removeWhere((key, _) => replaced.contains(key)),
      slotSizeConstraints: {...slotSizeConstraints}
        ..removeWhere((key, _) => replaced.contains(key)),
      slotLabels: {...slotLabels}
        ..removeWhere((key, _) => replaced.contains(key)),
    );
  }

  NativeComponentConfig withoutSlot(String id) => NativeComponentConfig(
    useDefaultNavigation: useDefaultNavigation,
    placements: {
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    },
    slotTypes: {...slotTypes}..remove(id),
    regions: {
      ...regions,
      for (final entry in placements.entries)
        if (entry.value.contains(id) && isEnabled(entry.key)) entry.key: true,
    },
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
    slotLabels: {...slotLabels}..remove(id),
  );

  NativeComponentConfig withSlotMoved(
    String id,
    String region, {
    String? beforeId,
    String? afterId,
  }) {
    if (!placements.values.any((ids) => ids.contains(id))) {
      throw ArgumentError.value(id, 'id', 'Unknown native slot.');
    }
    if (region.trim().isEmpty ||
        (beforeId != null && afterId != null) ||
        (beforeId != null && !slotsOf(region).contains(beforeId)) ||
        (afterId != null && !slotsOf(region).contains(afterId))) {
      throw ArgumentError(
        'Invalid native slot destination or insertion point.',
      );
    }
    if (beforeId == id || afterId == id) return this;
    final next = {
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    };
    final destination = next.putIfAbsent(region, () => []);
    final index = beforeId != null
        ? destination.indexOf(beforeId)
        : afterId != null
        ? destination.indexOf(afterId) + 1
        : destination.length;
    destination.insert(index, id);
    if (isEnabled(region) &&
        next.length == placements.length &&
        next.entries.every(
          (entry) => listEquals(entry.value, placements[entry.key]),
        )) {
      return this;
    }
    return NativeComponentConfig(
      useDefaultNavigation: useDefaultNavigation,
      placements: next,
      slotTypes: slotTypes,
      regions: {
        ...regions,
        for (final entry in placements.entries)
          if (entry.value.contains(id) && isEnabled(entry.key)) entry.key: true,
        region: true,
      },
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
  }

  NativeComponentConfig withSlotSize(String id, Size? size) =>
      NativeComponentConfig(
        useDefaultNavigation: useDefaultNavigation,
        placements: placements,
        slotTypes: slotTypes,
        regions: regions,
        slotPreferredSizes: {...slotPreferredSizes, id: size},
        slotSizeConstraints: {...slotSizeConstraints}..remove(id),
        slotLabels: slotLabels,
      );

  NativeComponentConfig withSlotSizeConstraints(
    String id,
    SlotSizeConstraints constraints,
  ) => NativeComponentConfig(
    useDefaultNavigation: useDefaultNavigation,
    placements: placements,
    slotTypes: slotTypes,
    regions: regions,
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints, id: constraints},
    slotLabels: slotLabels,
  );

  /// Names the slot instance [id]; a null or blank [label] restores the
  /// component's own name.
  NativeComponentConfig withSlotLabel(String id, String? label) =>
      NativeComponentConfig(
        useDefaultNavigation: useDefaultNavigation,
        placements: placements,
        slotTypes: slotTypes,
        regions: regions,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: {...slotLabels}
          ..remove(id)
          ..addAll({id: ?label}),
      );

  Map<String, Object> toJson() => {
    'useDefaultNavigation': ?useDefaultNavigation,
    'regions': regions,
    'placements': {
      for (final entry in placements.entries)
        entry.key: [
          for (final id in entry.value) {'id': id, 'type': slotTypeOf(id)},
        ],
    },
    if (slotPreferredSizes.isNotEmpty)
      'slotPreferredSizes': {
        for (final entry in slotPreferredSizes.entries)
          entry.key: entry.value == null
              ? null
              : [
                  entry.value!.width.isFinite ? entry.value!.width : null,
                  entry.value!.height.isFinite ? entry.value!.height : null,
                ],
      },
    if (slotSizeConstraints.isNotEmpty)
      'slotSizeConstraints': {
        for (final entry in slotSizeConstraints.entries)
          entry.key: entry.value.toJson(),
      },
    if (slotLabels.isNotEmpty) 'slotLabels': slotLabels,
  };

  factory NativeComponentConfig.fromJson(Object? value) {
    if (value is! Map || value['placements'] is! Map) {
      throw const FormatException('Invalid native component configuration.');
    }
    final rawRegions = value['regions'] ?? const {};
    final navigation = value['useDefaultNavigation'];
    if (navigation != null && navigation is! bool) {
      throw const FormatException('Invalid default navigation preference.');
    }
    if (rawRegions is! Map ||
        rawRegions.entries.any(
          (entry) => entry.key is! String || entry.value is! bool,
        )) {
      throw const FormatException('Invalid native region activation.');
    }
    final placements = <String, List<String>>{};
    final types = <String, String>{};
    for (final entry in (value['placements'] as Map).entries) {
      if (entry.key is! String || entry.value is! List) {
        throw const FormatException('Invalid native region.');
      }
      final ids = <String>[];
      for (final slot in entry.value as List) {
        if (slot is String && slot.trim().isNotEmpty) {
          ids.add(slot);
          types[slot] = JsonComponentType.normalize(slot, id: slot);
          continue;
        }
        if (slot is! Map || slot['id'] is! String || slot['type'] is! String) {
          throw const FormatException('Invalid native slot.');
        }
        final id = slot['id'] as String;
        ids.add(id);
        types[id] = JsonComponentType.normalize(
          slot['type'] as String,
          id: id,
        );
      }
      placements[entry.key as String] = ids;
    }
    try {
      final rawSizes = value['slotPreferredSizes'] ?? const {};
      final rawConstraints = value['slotSizeConstraints'] ?? const {};
      if (rawSizes is! Map || rawConstraints is! Map) {
        throw const FormatException('Invalid native slot sizes.');
      }
      final rawLabels = value['slotLabels'] ?? const {};
      if (rawLabels is! Map ||
          rawLabels.entries.any(
            (entry) => entry.key is! String || entry.value is! String,
          )) {
        throw const FormatException('Invalid native slot labels.');
      }
      if (rawConstraints.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid native slot constraint ID.');
      }
      final sizes = <String, Size?>{};
      for (final entry in rawSizes.entries) {
        final size = entry.value;
        if (entry.key is! String) {
          throw const FormatException('Invalid native slot size.');
        }
        sizes[entry.key as String] = JsonDimension.parsePreferredSize(
          size,
          allowInfiniteSides: true,
        );
      }
      return NativeComponentConfig(
        useDefaultNavigation: navigation as bool?,
        placements: placements,
        slotTypes: types,
        regions: Map<String, bool>.from(rawRegions),
        slotPreferredSizes: sizes,
        slotSizeConstraints: {
          for (final entry in rawConstraints.entries)
            entry.key as String: SlotSizeConstraints.fromJson(entry.value),
        },
        slotLabels: Map<String, String>.from(rawLabels),
      );
    } on ArgumentError {
      throw const FormatException('Invalid native region or slot IDs.');
    }
  }
}
