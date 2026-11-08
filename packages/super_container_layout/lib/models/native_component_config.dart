/// Configuration persistée ([NativeComponentConfig]) des composants Material natifs.
///
/// Stocke l'activation des régions, les placements par région, les contraintes
/// de slots et les propriétés natives (`AppBar`, `BottomAppBar`, `BottomNavigationBar`,
/// `NavigationRail`, `Card`, `Expansible`, `MenuAnchor`).
library;

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
    for (final descriptor in superMenuAnchorPropertyDescriptors)
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
       placements = JsonReader.normalizePlacements(
         placements,
         dropEmptyZones: false,
       ),
       slotTypes = Map.unmodifiable(slotTypes),
       regions = Map.unmodifiable(regions),
       regionAxes = Map.unmodifiable(regionAxes),
       regionFlows = JsonReader.normalizeZoneFlows(regionFlows),
       regionSizes = Map.unmodifiable(regionSizes),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = JsonReader.normalizeSlotLabels(slotLabels) {
    if (regionSizes.values.any((size) => !size.isFinite || size <= 0) ||
        JsonReader.hasInvalidSlotContainerMaps(
          placements: this.placements,
          slotTypes: this.slotTypes,
          zoneAxes: this.regionAxes,
          zoneFlows: this.regionFlows,
          slotPreferredSizes: this.slotPreferredSizes,
          slotSizeConstraints: this.slotSizeConstraints,
          slotLabels: this.slotLabels,
          extraZoneKeys: [...this.regions.keys, ...this.regionSizes.keys],
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
  bool? get consumeOutsideTap => boolProperty('consumeOutsideTap');
  String? get toggleIcon => stringProperty('toggleIcon');
  String? get toggleIconPosition => stringProperty('toggleIconPosition');
  double? get alignmentOffsetX => doubleProperty('alignmentOffsetX');
  double? get alignmentOffsetY => doubleProperty('alignmentOffsetY');
  Offset? get alignmentOffset {
    final dx = alignmentOffsetX;
    final dy = alignmentOffsetY;
    if (dx == null && dy == null) return null;
    return Offset(dx ?? 0, dy ?? 0);
  }

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
    final next = JsonReader.replaceSlotInMaps(
      id: id,
      replacementId: replacementId,
      type: type,
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
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

  NativeComponentConfig withConsumeOutsideTap(bool? consume) =>
      withProperty('consumeOutsideTap', consume);

  NativeComponentConfig withToggleIcon(String? style) =>
      withProperty('toggleIcon', style);

  NativeComponentConfig withToggleIconPosition(String? position) =>
      withProperty('toggleIconPosition', position);

  NativeComponentConfig withAlignmentOffsetX(double? dx) =>
      withProperty('alignmentOffsetX', dx);

  NativeComponentConfig withAlignmentOffsetY(double? dy) =>
      withProperty('alignmentOffsetY', dy);

  NativeComponentConfig withAlignmentOffset(Offset? offset) =>
      withAlignmentOffsetX(offset?.dx).withAlignmentOffsetY(offset?.dy);

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
  }) => copyWith(
    regionAxes: JsonReader.updateZoneAxisMap(
      regionAxes,
      region,
      axis,
      defaultAxis: defaultAxis,
    ),
  );

  NativeComponentConfig withRegionFlow(String region, ZoneFlowConfig flow) =>
      copyWith(
        regionFlows: JsonReader.updateZoneFlowMap(regionFlows, region, flow),
      );

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
    final next = JsonReader.addSlotToMaps(
      id: id,
      zone: region,
      type: type,
      replace: replace,
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      regions: {...regions, region: true},
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  NativeComponentConfig withoutSlot(String id) {
    final next = JsonReader.removeSlotsFromMaps(
      removedIds: {id},
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      regions: {
        ...regions,
        for (final entry in placements.entries)
          if (entry.value.contains(id) && isEnabled(entry.key)) entry.key: true,
      },
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  NativeComponentConfig withSlotMoved(
    String id,
    String region, {
    String? beforeId,
    String? afterId,
  }) {
    final next = JsonReader.moveSlotInPlacements(
      id: id,
      zone: region,
      beforeId: beforeId,
      afterId: afterId,
      placements: placements,
      unknownError: 'Unknown native slot.',
      destinationError: 'Invalid native slot destination or insertion point.',
    );
    if (next == null) return this;
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
    final slotJson = JsonReader.encodeSlotContainerJson(
      placements: placements,
      slotTypeOf: slotTypeOf,
      zoneAxes: regionAxes,
      zoneFlows: regionFlows,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
      alwaysIncludePlacements: true,
      useShortTypeNameInFullJson: false,
      allowBareSlotIdInFullJson: false,
      axesKey: 'regionAxes',
      flowsKey: 'regionFlows',
    );
    return {
      if (binding != null) 'binding': binding!.toJson(),
      ...properties,
      'regions': regions,
      if (slotJson['regionAxes'] case final Object axes) 'regionAxes': axes,
      if (slotJson['regionFlows'] case final Object flows) 'regionFlows': flows,
      if (regionSizes.isNotEmpty) 'regionSizes': regionSizes,
      'placements': slotJson['placements']!,
      if (slotJson['slotPreferredSizes'] case final Object sizes)
        'slotPreferredSizes': sizes,
      if (slotJson['slotSizeConstraints'] case final Object constraints)
        'slotSizeConstraints': constraints,
      if (slotJson['slotLabels'] case final Object labels) 'slotLabels': labels,
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
    final (:placements, :slotTypes) = JsonReader.parseSlotPlacements(
      value['placements'],
      invalidPlacementsMessage: 'Invalid native component configuration.',
      invalidZoneMessage: 'Invalid native region.',
      invalidSlotMessage: 'Invalid native slot.',
    );
    try {
      final rawRegionSizes = value['regionSizes'] ?? const {};
      if (rawRegionSizes is! Map) {
        throw const FormatException('Invalid native region flow settings.');
      }
      final meta = JsonReader.parseSlotContainerMetadata(
        value,
        placedIds: placements.values.expand((ids) => ids),
        axesKey: 'regionAxes',
        flowsKey: 'regionFlows',
        invalidMetadataMessage: 'Invalid native slot sizes.',
        invalidLabelsMessage: 'Invalid native slot labels.',
        invalidAxisMessage: 'Invalid native region axis.',
        invalidFlowMessage: 'Invalid native region flow.',
        invalidConstraintMessage: 'Invalid native slot constraint ID.',
        invalidSizeMessage: 'Invalid native slot size.',
      );
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
        slotTypes: slotTypes,
        regions: {
          for (final entry in rawRegions.entries)
            if (!(entry.key == 'child' && entry.value == false))
              entry.key as String: entry.value as bool,
        },
        regionAxes: meta.zoneAxes,
        regionFlows: meta.zoneFlows,
        regionSizes: parsedRegionSizes,
        slotPreferredSizes: meta.slotPreferredSizes,
        slotSizeConstraints: meta.slotSizeConstraints,
        slotLabels: meta.slotLabels,
      );
    } on ArgumentError {
      throw const FormatException('Invalid native region or slot IDs.');
    }
  }
}

String _formatNativeDescriptorValue(
  NativePropertyDescriptor descriptor,
  Object value,
) => switch (descriptor.editorType) {
  NativePropertyEditorType.bool => (value as bool) ? 'Oui' : 'Non',
  NativePropertyEditorType.number =>
    JsonReader.formatNumber((value as num).toDouble()),
  NativePropertyEditorType.color =>
    value is Color ? JsonColor.toHex(value) : '$value',
  NativePropertyEditorType.select =>
    descriptor.options
            .where((option) => option.value == value)
            .firstOrNull
            ?.label ??
        '$value',
  NativePropertyEditorType.shape =>
    value is NativeShapeConfig
        ? value.kind.label
        : NativeShapeConfig.fromJson(value).kind.label,
};

/// Résumé des propriétés d'un [NativeComponentConfig] pour l'info-bulle du menu contextuel.
String formatNativeComponentTooltip({
  required String title,
  required NativeComponentConfig config,
  List<({String label, int count, bool enabled})> regions = const [],
  List<NativePropertyDescriptor> propertyDescriptors = const [],
}) {
  final activeRegions = [
    for (final region in regions)
      if (region.enabled) '${region.label} (${region.count})',
  ];
  final inactiveRegions = [
    for (final region in regions)
      if (!region.enabled) region.label,
  ];
  final configuredProps = <String>[];
  final defaultProps = <String>[];
  for (final descriptor in propertyDescriptors) {
    final raw = config.property(descriptor.id);
    if (raw != null) {
      configuredProps.add(
        '${descriptor.label} : ${_formatNativeDescriptorValue(descriptor, raw)}',
      );
    } else if (descriptor.defaultValue != null) {
      defaultProps.add(
        '${descriptor.label} : ${_formatNativeDescriptorValue(descriptor, descriptor.defaultValue!)}',
      );
    }
  }
  final propSummary = configuredProps.isNotEmpty
      ? configuredProps
      : defaultProps.take(3).toList();
  return [
    title,
    if (activeRegions.isNotEmpty)
      'Zones actives : ${activeRegions.join(', ')}'
    else if (regions.isNotEmpty)
      'Zones actives : Aucune',
    if (inactiveRegions.isNotEmpty)
      'Zones masquées : ${inactiveRegions.join(', ')}',
    if (config.binding != null)
      'Liaison : ${config.binding!.repositoryId ?? 'Hérité'} → ${config.binding!.path}',
    if (propSummary.isNotEmpty) propSummary.join(' · '),
  ].join('\n');
}

