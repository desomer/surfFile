import 'component_config.dart';
import 'native_component_config.dart';

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

/// Typed compatibility API for Scaffold configurations.
class ScaffoldPageConfig extends ComponentConfig {
  ScaffoldPageConfig({
    Map<ScaffoldPageRegion, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<ScaffoldPageRegion, bool> regions = const {},
  }) : this.fromNative(
         NativeComponentConfig(
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
