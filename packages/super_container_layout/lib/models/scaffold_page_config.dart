import 'dart:ui' show Clip;

import 'package:flutter/painting.dart' show Axis;

import 'component_config.dart';
import 'native_component_config.dart';
import 'native_property_descriptor.dart';

/// Native content regions owned by a `Scaffold`.
enum ScaffoldPageRegion {
  appBar,
  body,
  drawer,
  endDrawer,
  bottomNavigationBar,
  floatingActionButton,
  bottomSheet,
}

/// Mode d'affichage et de défilement de la zone `body` du `Scaffold`.
enum ScaffoldBodyMode {
  /// Zone `body` fixe occupant tout l'espace disponible (`SizedBox.expand`).
  standard,

  /// Zone `body` englobée dans un `SingleChildScrollView`.
  singleChildScrollView,

  /// Page en mode `CustomScrollView` (avec slivers pour `appBar` et `body`).
  customScrollView;

  static ScaffoldBodyMode fromName(String? name) => switch (name) {
    'singleChildScrollView' => ScaffoldBodyMode.singleChildScrollView,
    'customScrollView' => ScaffoldBodyMode.customScrollView,
    _ => ScaffoldBodyMode.standard,
  };
}

/// Typed compatibility API for Scaffold configurations.
class ScaffoldPageConfig extends ComponentConfig {
  static const List<NativePropertyDescriptor> propertyDescriptors =
      scaffoldPagePropertyDescriptors;

  ScaffoldPageConfig({
    Map<ScaffoldPageRegion, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<ScaffoldPageRegion, bool> regions = const {},
    Map<String, Object> properties = const {},
    ScaffoldBodyMode? bodyMode,
    Axis? scrollDirection,
    bool? reverse,
    bool? primary,
    double? scrollPadding,
    Clip? clipBehavior,
  }) : this.fromNative(
         NativeComponentConfig(
           properties: {
             ...properties,
             if (bodyMode != null && bodyMode != ScaffoldBodyMode.standard)
               'bodyMode': bodyMode.name,
             if (scrollDirection != null)
               'scrollDirection': scrollDirection.name,
             if (reverse != null) 'reverse': reverse,
             if (primary != null) 'primary': primary,
             if (scrollPadding != null) 'scrollPadding': scrollPadding,
             if (clipBehavior != null) 'clipBehavior': clipBehavior.name,
           },
           placements: {
             for (final entry in placements.entries)
               entry.key.name: entry.value,
           },
           slotTypes: slotTypes,
           regions: {
             for (final entry in regions.entries) entry.key.name: entry.value,
           },
         ),
       );

  ScaffoldPageConfig.fromNative(this.native) {
    final names = ScaffoldPageRegion.values.map((region) => region.name).toSet();
    if (native.regions['body'] == false ||
        native.regions.keys.any((name) => !names.contains(name)) ||
        native.placements.keys.any((name) => !names.contains(name))) {
      throw ArgumentError('Invalid Scaffold regions; body must remain enabled.');
    }
  }

  final NativeComponentConfig native;

  Map<ScaffoldPageRegion, List<String>> get placements => Map.unmodifiable({
    for (final region in ScaffoldPageRegion.values)
      if (native.placements.containsKey(region.name))
        region: native.slotsOf(region.name),
  });
  Map<String, String> get slotTypes => native.slotTypes;
  Map<ScaffoldPageRegion, bool> get regions => Map.unmodifiable({
    for (final region in ScaffoldPageRegion.values)
      if (native.regions.containsKey(region.name))
        region: native.regions[region.name]!,
  });

  ScaffoldBodyMode get bodyMode =>
      ScaffoldBodyMode.fromName(native.stringProperty('bodyMode'));

  Axis get scrollDirection => switch (native.stringProperty('scrollDirection')) {
    'horizontal' => Axis.horizontal,
    _ => Axis.vertical,
  };

  bool get reverse => native.boolProperty('reverse') ?? false;

  bool? get primary => native.boolProperty('primary');

  double? get scrollPadding => native.doubleProperty('scrollPadding');

  Clip? get clipBehavior => switch (native.stringProperty('clipBehavior')) {
    'none' => Clip.none,
    'hardEdge' => Clip.hardEdge,
    'antiAlias' => Clip.antiAlias,
    'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
    _ => null,
  };

  bool isEnabled(ScaffoldPageRegion region) =>
      region == ScaffoldPageRegion.body || native.isEnabled(region.name);
  String slotTypeOf(String id) => native.slotTypeOf(id);
  List<String> slotsOf(ScaffoldPageRegion region) => native.slotsOf(region.name);
  ScaffoldPageConfig withRegionEnabled(ScaffoldPageRegion region, bool enabled) =>
      ScaffoldPageConfig.fromNative(native.withRegionEnabled(region.name, enabled));
  ScaffoldPageConfig withSlotAdded(String id, ScaffoldPageRegion region, {String? type}) =>
      ScaffoldPageConfig.fromNative(native.withSlotAdded(id, region.name, type: type));
  ScaffoldPageConfig withoutSlot(String id) =>
      ScaffoldPageConfig.fromNative(native.withoutSlot(id));
  ScaffoldPageConfig withProperty(String id, Object? value) =>
      ScaffoldPageConfig.fromNative(native.withProperty(id, value));
  ScaffoldPageConfig withBodyMode(ScaffoldBodyMode? mode) =>
      withProperty(
        'bodyMode',
        mode == null || mode == ScaffoldBodyMode.standard ? null : mode.name,
      );
  ScaffoldPageConfig withScrollDirection(Axis? direction) =>
      withProperty('scrollDirection', direction?.name);
  ScaffoldPageConfig withReverse(bool? reverse) =>
      withProperty('reverse', reverse);
  ScaffoldPageConfig withPrimary(bool? primary) =>
      withProperty('primary', primary);
  ScaffoldPageConfig withScrollPadding(double? padding) =>
      withProperty('scrollPadding', padding);
  ScaffoldPageConfig withClipBehavior(Clip? clip) =>
      withProperty('clipBehavior', clip?.name);

  @override
  String get componentType => 'scaffold';

  @override
  ScaffoldPageConfig patchFromJson(Map<Object?, Object?> patch) =>
      ScaffoldPageConfig.fromJson({...toJson(), ...patch});

  @override
  Map<String, Object> toJson() => native.toJson();

  factory ScaffoldPageConfig.fromJson(Object? value) {
    try {
      return ScaffoldPageConfig.fromNative(NativeComponentConfig.fromJson(value));
    } on ArgumentError {
      throw const FormatException('Invalid Scaffold regions.');
    }
  }
}
