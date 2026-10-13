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

/// Slot placement for a page rendered directly by Flutter's `Scaffold`.
class ScaffoldPageConfig {
  ScaffoldPageConfig({
    Map<ScaffoldPageRegion, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<ScaffoldPageRegion, bool> regions = const {},
  }) : placements = Map.unmodifiable({
         for (final entry in placements.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       slotTypes = Map.unmodifiable(slotTypes),
       regions = Map.unmodifiable(regions) {
    if (regions[ScaffoldPageRegion.body] == false) {
      throw ArgumentError('The Scaffold body must remain enabled.');
    }
    final ids = placements.values.expand((ids) => ids).toList();
    if (ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length ||
        slotTypes.keys.any((id) => id.trim().isEmpty) ||
        slotTypes.values.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        placements,
        'placements',
        'Slot IDs must be unique and non-empty.',
      );
    }
  }

  final Map<ScaffoldPageRegion, List<String>> placements;
  final Map<String, String> slotTypes;
  final Map<ScaffoldPageRegion, bool> regions;

  bool isEnabled(ScaffoldPageRegion region) =>
      region == ScaffoldPageRegion.body ||
      (regions[region] ?? slotsOf(region).isNotEmpty);

  ScaffoldPageConfig withRegionEnabled(
    ScaffoldPageRegion region,
    bool enabled,
  ) => ScaffoldPageConfig(
    placements: placements,
    slotTypes: slotTypes,
    regions: {...regions, region: enabled},
  );

  String slotTypeOf(String id) => slotTypes[id] ?? id;

  List<String> slotsOf(ScaffoldPageRegion region) =>
      placements[region] ?? const [];

  ScaffoldPageConfig withSlotAdded(
    String id,
    ScaffoldPageRegion region, {
    String? type,
  }) {
    final next = {
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    }..putIfAbsent(region, () => []).add(id);
    final types = {...slotTypes}..remove(id);
    if (type != null && type != id) types[id] = type;
    return ScaffoldPageConfig(
      placements: next,
      slotTypes: types,
      regions: {...regions, region: true},
    );
  }

  ScaffoldPageConfig withoutSlot(String id) => ScaffoldPageConfig(
    placements: {
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    },
    slotTypes: {...slotTypes}..remove(id),
    regions: regions,
  );

  Map<String, Object> toJson() => {
    'regions': {
      for (final entry in regions.entries) entry.key.name: entry.value,
    },
    'placements': {
      for (final entry in placements.entries)
        entry.key.name: [
          for (final id in entry.value) {'id': id, 'type': slotTypeOf(id)},
        ],
    },
  };

  factory ScaffoldPageConfig.fromJson(Object? value) {
    if (value is! Map || value['placements'] is! Map) {
      throw const FormatException('Configuration de page Scaffold invalide.');
    }
    final rawPlacements = value['placements'] as Map;
    final rawRegions = value['regions'] ?? const {};
    if (rawRegions is! Map ||
        rawRegions.entries.any(
          (entry) =>
              !ScaffoldPageRegion.values.any(
                (region) => region.name == entry.key,
              ) ||
              entry.value is! bool,
        )) {
      throw const FormatException('Activation des régions Scaffold invalide.');
    }
    final placements = <ScaffoldPageRegion, List<String>>{};
    for (final entry in rawPlacements.entries) {
      final region = ScaffoldPageRegion.values
          .where((candidate) => candidate.name == entry.key)
          .firstOrNull;
      final ids = entry.value;
      if (region == null ||
          ids is! List ||
          ids.any(
            (slot) =>
                slot is! Map ||
                slot['id'] is! String ||
                (slot['id'] as String).trim().isEmpty ||
                slot['type'] is! String ||
                (slot['type'] as String).trim().isEmpty,
          )) {
        throw const FormatException('Région Scaffold invalide.');
      }
      placements[region] = [
        for (final slot in ids) (slot as Map)['id'] as String,
      ];
    }
    try {
      return ScaffoldPageConfig(
        regions: {
          for (final entry in rawRegions.entries)
            ScaffoldPageRegion.values.firstWhere(
              (region) => region.name == entry.key,
            ): entry.value as bool,
        },
        placements: placements,
        slotTypes: {
          for (final regionSlots in rawPlacements.values)
            for (final slot in regionSlots as List)
              if ((slot as Map)['type'] != slot['id'])
                slot['id'] as String: slot['type'] as String,
        },
      );
    } on ArgumentError {
      throw const FormatException('Identifiants de slot Scaffold invalides.');
    }
  }
}
