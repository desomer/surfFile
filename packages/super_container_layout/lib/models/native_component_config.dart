import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart' show Axis, ShapeBorder;

import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'native_property_descriptor.dart';
import 'native_shape_config.dart';
import 'super_layout_config.dart' show SlotSizeConstraints, ZoneFlowConfig;

/// Immutable placements shared by adapters for native Flutter components.
class NativeComponentConfig extends ComponentConfig {
  static const Set<String> _reservedJsonKeys = {
    'type',
    'binding',
    'regions',
    'regionAxes',
    'regionFlows',
    'regionSizes',
    'placements',
    'slotPreferredSizes',
    'slotSizeConstraints',
    'slotLabels',
  };

  static final Map<String, NativePropertyDescriptor> _knownDescriptors = {
    useDefaultNavigationPropertyDescriptor.id:
        useDefaultNavigationPropertyDescriptor,
    for (final descriptor in superAppBarPropertyDescriptors)
      descriptor.id: descriptor,
    for (final descriptor in superSliverAppBarPropertyDescriptors)
      descriptor.id: descriptor,
    for (final descriptor in superBottomAppBarPropertyDescriptors)
      descriptor.id: descriptor,
    for (final descriptor in superBottomNavigationBarPropertyDescriptors)
      descriptor.id: descriptor,
    for (final descriptor in superExpansiblePropertyDescriptors)
      descriptor.id: descriptor,
    for (final descriptor in scaffoldPagePropertyDescriptors)
      descriptor.id: descriptor,
  };

  static Object _normalizeProperty(String id, Object value) {
    final trimmed = id.trim();
    if (trimmed.isEmpty || _reservedJsonKeys.contains(trimmed)) {
      throw ArgumentError.value(id, 'id', 'Invalid native property ID.');
    }
    if (trimmed == 'fixedColor') {
      return JsonColor.toHex(JsonColor.parse(value, trimmed));
    }
    final descriptor = _knownDescriptors[trimmed];
    if (descriptor != null) {
      return descriptor.normalizeValue(value)!;
    }
    if (value is NativeShapeConfig) return value.toJson();
    if (value is Color) return JsonColor.toHex(value);
    if (value is bool || value is String) return value;
    if (value is num && value.isFinite) return value.toDouble();
    if (value is Map) return Map<String, Object?>.unmodifiable(value);
    throw FormatException('Valeur invalide pour la propriété "$trimmed".');
  }

  NativeComponentConfig({
    this.binding,
    Map<String, Object> properties = const {},
    Map<String, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<String, bool> regions = const {},
    Map<String, Axis> regionAxes = const {},
    Map<String, ZoneFlowConfig> regionFlows = const {},
    Map<String, double> regionSizes = const {},
    Map<String, Size?> slotPreferredSizes = const {},
    Map<String, SlotSizeConstraints> slotSizeConstraints = const {},
    Map<String, String> slotLabels = const {},
  }) : properties = Map.unmodifiable({
         for (final entry in properties.entries)
           entry.key.trim(): _normalizeProperty(entry.key, entry.value),
       }),
       placements = Map.unmodifiable({
         for (final entry in placements.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       slotTypes = Map.unmodifiable(slotTypes),
       regions = Map.unmodifiable(regions),
       regionAxes = Map.unmodifiable(regionAxes),
       regionFlows = Map.unmodifiable({
         for (final entry in regionFlows.entries)
           if (!entry.value.isDefault) entry.key: entry.value,
       }),
       regionSizes = Map.unmodifiable(regionSizes),
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
        regionAxes.keys.any((id) => id.trim().isEmpty) ||
        regionFlows.keys.any((id) => id.trim().isEmpty) ||
        regionSizes.keys.any((id) => id.trim().isEmpty) ||
        regionSizes.values.any((size) => !size.isFinite || size <= 0) ||
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

  /// Optional boolean repository binding for stateful native adapters (e.g. Expansible).
  final JsonTextBinding? binding;

  /// Generic style and behavior properties stored flat at the root of the JSON config.
  final Map<String, Object> properties;
  final Map<String, String> slotTypes;
  final Map<String, bool> regions;
  final Map<String, Axis> regionAxes;
  final Map<String, ZoneFlowConfig> regionFlows;
  final Map<String, double> regionSizes;
  final Map<String, Size?> slotPreferredSizes;
  final Map<String, SlotSizeConstraints> slotSizeConstraints;

  /// Display names given to slot instances; a technical ID never changes.
  final Map<String, String> slotLabels;

  bool? get useDefaultNavigation => boolProperty('useDefaultNavigation');
  bool? get initiallyExpanded => boolProperty('initiallyExpanded');
  bool? get maintainState => boolProperty('maintainState');
  bool? get headerClickToggles => boolProperty('headerClickToggles');

  @override
  void validate() {
    binding?.validate();
  }

  bool isEnabled(String region) =>
      regions[region] ?? slotsOf(region).isNotEmpty;
  List<String> slotsOf(String region) => placements[region] ?? const [];
  String slotTypeOf(String id) => slotTypes[id] ?? id;
  Axis? regionAxisOf(String region) => regionAxes[region];
  ZoneFlowConfig regionFlowOf(String region) =>
      regionFlows[region] ?? const ZoneFlowConfig();
  double? regionSizeOf(String region) => regionSizes[region];

  Object? property(String id) => properties[id];
  bool? boolProperty(String id) => switch (properties[id]) {
    final bool value => value,
    _ => null,
  };
  double? doubleProperty(String id) => switch (properties[id]) {
    final num value => value.toDouble(),
    _ => null,
  };
  Color? colorProperty(String id) => switch (properties[id]) {
    final Color value => value,
    final Object value => JsonColor.parse(value, id),
    null => null,
  };
  String? stringProperty(String id) => switch (properties[id]) {
    final String value => value,
    _ => null,
  };
  NativeShapeConfig? shapeProperty(String id) => switch (properties[id]) {
    final NativeShapeConfig value => value,
    final Object value => NativeShapeConfig.fromJson(value),
    null => null,
  };
  ShapeBorder? shapeBorderProperty(String id) =>
      shapeProperty(id)?.toShapeBorder();

  NativeComponentConfig copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<String, Object>? properties,
    Map<String, List<String>>? placements,
    Map<String, String>? slotTypes,
    Map<String, bool>? regions,
    Map<String, Axis>? regionAxes,
    Map<String, ZoneFlowConfig>? regionFlows,
    Map<String, double>? regionSizes,
    Map<String, Size?>? slotPreferredSizes,
    Map<String, SlotSizeConstraints>? slotSizeConstraints,
    Map<String, String>? slotLabels,
  }) => NativeComponentConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    properties: properties ?? this.properties,
    placements: placements ?? this.placements,
    slotTypes: slotTypes ?? this.slotTypes,
    regions: regions ?? this.regions,
    regionAxes: regionAxes ?? this.regionAxes,
    regionFlows: regionFlows ?? this.regionFlows,
    regionSizes: regionSizes ?? this.regionSizes,
    slotPreferredSizes: slotPreferredSizes ?? this.slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints ?? this.slotSizeConstraints,
    slotLabels: slotLabels ?? this.slotLabels,
  );

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
    return copyWith(
      placements: {
        for (final entry in placements.entries)
          entry.key: [
            for (final slot in entry.value) slot == id ? replacementId : slot,
          ],
      },
      slotTypes: {...slotTypes}
        ..remove(id)
        ..[replacementId] = type,
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

  NativeComponentConfig withDefaultNavigation(bool? enabled) =>
      withProperty('useDefaultNavigation', enabled);

  NativeComponentConfig withInitiallyExpanded(bool? expanded) =>
      withProperty('initiallyExpanded', expanded);

  NativeComponentConfig withMaintainState(bool? maintain) =>
      withProperty('maintainState', maintain);

  NativeComponentConfig withHeaderClickToggles(bool? toggles) =>
      withProperty('headerClickToggles', toggles);

  NativeComponentConfig withBinding(JsonTextBinding? value) =>
      copyWith(binding: value, clearBinding: value == null);

  NativeComponentConfig withProperty(String id, Object? value) {
    final next = {...properties};
    final trimmed = id.trim();
    if (value == null) {
      next.remove(trimmed);
    } else {
      next[trimmed] = _normalizeProperty(trimmed, value);
    }
    return copyWith(properties: next);
  }

  /// Resets dialog settings and style properties while keeping placed slots.
  NativeComponentConfig withSettingsReset() => NativeComponentConfig(
    placements: placements,
    slotTypes: slotTypes,
    regions: const {},
    regionAxes: regionAxes,
    regionFlows: regionFlows,
    regionSizes: regionSizes,
    slotPreferredSizes: slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints,
    slotLabels: slotLabels,
  );

  NativeComponentConfig withRegionEnabled(String region, bool enabled) =>
      copyWith(regions: {...regions, region: enabled});

  NativeComponentConfig withRegionAxis(
    String region,
    Axis? axis, {
    Axis? defaultAxis,
  }) {
    final next = {...regionAxes};
    if (axis == null || axis == defaultAxis) {
      next.remove(region);
    } else {
      next[region] = axis;
    }
    return copyWith(regionAxes: next);
  }

  NativeComponentConfig withRegionFlow(String region, ZoneFlowConfig flow) {
    final next = {...regionFlows};
    if (flow.isDefault) {
      next.remove(region);
    } else {
      next[region] = flow;
    }
    return copyWith(regionFlows: next);
  }

  NativeComponentConfig withRegionSize(String region, double? size) {
    final next = {...regionSizes};
    if (size == null) {
      next.remove(region);
    } else {
      next[region] = size;
    }
    return copyWith(regionSizes: next);
  }

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
    return copyWith(
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

  NativeComponentConfig withoutSlot(String id) => copyWith(
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
    return copyWith(
      placements: next,
      regions: {
        ...regions,
        for (final entry in placements.entries)
          if (entry.value.contains(id) && isEnabled(entry.key)) entry.key: true,
        region: true,
      },
    );
  }

  NativeComponentConfig withSlotSize(String id, Size? size) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes, id: size},
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
  );

  NativeComponentConfig withSlotSizeConstraints(
    String id,
    SlotSizeConstraints constraints,
  ) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints, id: constraints},
  );

  /// Names the slot instance [id]; a null or blank [label] restores the
  /// component's own name.
  NativeComponentConfig withSlotLabel(String id, String? label) => copyWith(
    slotLabels: {...slotLabels}
      ..remove(id)
      ..addAll({id: ?label}),
  );

  @override
  String get componentType => 'native';

  @override
  NativeComponentConfig patchFromJson(Map<Object?, Object?> patch) =>
      NativeComponentConfig.fromJson({...toJson(), ...patch});

  @override
  Map<String, Object> toJson() {
    validate();
    return {
      if (binding != null) 'binding': binding!.toJson(),
      ...properties,
      'regions': regions,
      if (regionAxes.isNotEmpty)
        'regionAxes': {
          for (final entry in regionAxes.entries) entry.key: entry.value.name,
        },
      if (regionFlows.isNotEmpty)
        'regionFlows': {
          for (final entry in regionFlows.entries)
            if (!entry.value.isDefault) entry.key: entry.value.toJson(),
        },
      if (regionSizes.isNotEmpty) 'regionSizes': regionSizes,
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
  }

  factory NativeComponentConfig.fromJson(Object? value) {
    if (value is! Map || value['placements'] is! Map) {
      throw const FormatException('Invalid native component configuration.');
    }
    final rawRegions = value['regions'] ?? const {};
    final binding = value.containsKey('binding') && value['binding'] != null
        ? JsonTextBinding.fromJson(value['binding'])
        : null;
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
        types[id] = JsonComponentType.normalize(slot['type'] as String, id: id);
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
      final rawAxes = value['regionAxes'] ?? const {};
      final rawFlows = value['regionFlows'] ?? const {};
      final rawRegionSizes = value['regionSizes'] ?? const {};
      if (rawAxes is! Map || rawFlows is! Map || rawRegionSizes is! Map) {
        throw const FormatException('Invalid native region flow settings.');
      }
      final parsedAxes = <String, Axis>{};
      for (final entry in rawAxes.entries) {
        if (entry.key is! String) {
          throw const FormatException('Invalid native region axis.');
        }
        final axis = Axis.values
            .where((candidate) => candidate.name == entry.value)
            .firstOrNull;
        if (axis == null) {
          throw const FormatException('Invalid native region axis.');
        }
        parsedAxes[entry.key as String] = axis;
      }
      final parsedFlows = <String, ZoneFlowConfig>{};
      for (final entry in rawFlows.entries) {
        if (entry.key is! String) {
          throw const FormatException('Invalid native region flow.');
        }
        parsedFlows[entry.key as String] = ZoneFlowConfig.fromJson(entry.value);
      }
      final parsedRegionSizes = <String, double>{};
      for (final entry in rawRegionSizes.entries) {
        final rawSize = entry.value;
        if (entry.key is! String ||
            rawSize is! num ||
            !rawSize.isFinite ||
            rawSize <= 0) {
          throw const FormatException('Invalid native region size.');
        }
        parsedRegionSizes[entry.key as String] = rawSize.toDouble();
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
      final parsedProperties = <String, Object>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('Invalid native property key.');
        }
        final trimmed = key.trim();
        if (_reservedJsonKeys.contains(trimmed)) continue;
        if (entry.value == null) continue;
        parsedProperties[trimmed] = _normalizeProperty(trimmed, entry.value!);
      }
      return NativeComponentConfig(
        binding: binding,
        properties: parsedProperties,
        placements: placements,
        slotTypes: types,
        regions: {
          for (final entry in rawRegions.entries)
            if (!(entry.key == 'child' && entry.value == false))
              entry.key as String: entry.value as bool,
        },
        regionAxes: parsedAxes,
        regionFlows: parsedFlows,
        regionSizes: parsedRegionSizes,
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
