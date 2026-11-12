/// Configuration persistée ([SuperConditionalConfig]) d'un composant conditionnel [SuperConditional].
///
/// Permet d'associer chaque valeur possible d'une liaison de repository JSON
/// ([JsonTextBinding]) à une zone de contenu dédiée (`'case:<valeur>'`), avec
/// une zone de repli optionnelle (`'default'`).
library;

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show Axis;

import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'super_layout_config.dart' show SlotSizeConstraints, ZoneFlowConfig;

/// Configuration persistée d'un composant conditionnel [SuperConditional].
@immutable
class SuperConditionalConfig extends ComponentConfig {
  SuperConditionalConfig({
    this.binding,
    List<String> cases = const [],
    this.hasDefaultCase = true,
    this.initialCase = '',
    this.maintainState = false,
    this.emptyText = '',
    Map<String, List<String>> placements = const {},
    Map<String, String> slotTypes = const {},
    Map<String, Axis> zoneAxes = const {},
    Map<String, ZoneFlowConfig> zoneFlows = const {},
    Map<String, Size?> slotPreferredSizes = const {},
    Map<String, SlotSizeConstraints> slotSizeConstraints = const {},
    Map<String, String> slotLabels = const {},
  }) : cases = _normalizeCases(cases, placements),
       placements = JsonReader.normalizePlacements(placements),
       slotTypes = Map.unmodifiable(slotTypes),
       zoneAxes = Map.unmodifiable(zoneAxes),
       zoneFlows = JsonReader.normalizeZoneFlows(zoneFlows),
       slotPreferredSizes = Map.unmodifiable(slotPreferredSizes),
       slotSizeConstraints = Map.unmodifiable(slotSizeConstraints),
       slotLabels = JsonReader.normalizeSlotLabels(slotLabels) {
    if (_hasInvalidCases(cases) ||
        JsonReader.hasInvalidSlotContainerMaps(
          placements: this.placements,
          slotTypes: this.slotTypes,
          zoneAxes: this.zoneAxes,
          zoneFlows: this.zoneFlows,
          slotPreferredSizes: this.slotPreferredSizes,
          slotSizeConstraints: this.slotSizeConstraints,
          slotLabels: this.slotLabels,
        )) {
      throw ArgumentError('Invalid SuperConditional configuration.');
    }
  }

  /// Nom de la zone de contenu par défaut (affichée si aucun cas ne correspond).
  static const String defaultZone = 'default';

  /// Préfixe des zones de contenu associées à chaque cas nommé.
  static const String caseZonePrefix = 'case:';

  /// Retourne l'identifiant de zone pour la valeur de cas [caseValue] (`'case:<caseValue>'`).
  static String caseZoneFor(String caseValue) => '$caseZonePrefix$caseValue';

  /// Extrait la valeur de cas d'un identifiant de zone `'case:<caseValue>'`, ou `null`.
  static String? caseValueOfZone(String zone) =>
      zone.startsWith(caseZonePrefix) && zone.length > caseZonePrefix.length
      ? zone.substring(caseZonePrefix.length)
      : null;

  static bool _hasInvalidCases(List<String> rawCases) {
    final seen = <String>{};
    for (final item in rawCases) {
      final trimmed = item.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        return true;
      }
    }
    return false;
  }

  static List<String> _normalizeCases(
    List<String> rawCases,
    Map<String, List<String>> placements,
  ) {
    final ordered = <String>[];
    final seen = <String>{};
    for (final item in rawCases) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        ordered.add(trimmed);
      }
    }
    for (final zone in placements.keys) {
      final caseVal = caseValueOfZone(zone)?.trim();
      if (caseVal != null && caseVal.isNotEmpty && seen.add(caseVal)) {
        ordered.add(caseVal);
      }
    }
    return List<String>.unmodifiable(ordered);
  }

  /// Liaison vers l'attribut du repository JSON déterminant la branche active.
  final JsonTextBinding? binding;

  /// Liste ordonnée des valeurs de cas gérées par ce composant.
  final List<String> cases;

  /// Active une zone de repli `'default'` lorsque la valeur ne correspond à aucun cas.
  final bool hasDefaultCase;

  /// Valeur de cas sélectionnée initialement (ou `'default'`).
  final String initialCase;

  /// Conserve l'état des branches inactives en mémoire (`IndexedStack`).
  final bool maintainState;

  /// Message optionnel affiché hors édition lorsqu'aucune branche ne correspond.
  final String emptyText;

  final Map<String, List<String>> placements;
  final Map<String, String> slotTypes;
  final Map<String, Axis> zoneAxes;
  final Map<String, ZoneFlowConfig> zoneFlows;
  final Map<String, Size?> slotPreferredSizes;
  final Map<String, SlotSizeConstraints> slotSizeConstraints;
  final Map<String, String> slotLabels;

  @override
  String get componentType => 'conditional';

  @override
  Iterable<JsonTextBinding> get referencedBindings => [?binding];

  @override
  Map<String, String> get childSlots => {
    for (final id in {
      ...placements.values.expand((ids) => ids),
      ...slotTypes.keys,
      ...slotPreferredSizes.keys,
      ...slotSizeConstraints.keys,
      ...slotLabels.keys,
    })
      id: slotTypeOf(id),
  };

  @override
  SuperConditionalConfig copyWithRemappedSlots(
    String Function(String id) remap,
  ) {
    final currentSlots = childSlots;
    return copyWith(
      placements: {
        for (final entry in placements.entries)
          entry.key: [for (final id in entry.value) remap(id)],
      },
      slotTypes: {
        for (final entry in slotTypes.entries) remap(entry.key): entry.value,
        for (final MapEntry(key: id, value: type) in currentSlots.entries)
          if (remap(id) != type) remap(id): type,
      },
      slotPreferredSizes: {
        for (final entry in slotPreferredSizes.entries)
          remap(entry.key): entry.value,
      },
      slotSizeConstraints: {
        for (final entry in slotSizeConstraints.entries)
          remap(entry.key): entry.value,
      },
      slotLabels: {
        for (final entry in slotLabels.entries) remap(entry.key): entry.value,
      },
    );
  }

  @override
  void validate() {
    binding?.validate();
    final seen = <String>{};
    for (final item in cases) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        throw const FormatException('Un nom de cas ne peut pas être vide.');
      }
      if (!seen.add(trimmed)) {
        throw FormatException('Cas conditionnel en doublon : "$trimmed".');
      }
    }
    for (final constraint in slotSizeConstraints.values) {
      SlotSizeConstraints.fromJson(constraint.toJson());
    }
  }

  /// Toutes les zones actives selon la configuration (`'case:<v>'` + `'default'` si activé).
  List<String> get activeZones => [
    for (final c in cases) caseZoneFor(c),
    if (hasDefaultCase) defaultZone,
  ];

  /// Retourne la zone correspondant à [boundValue] (ou [defaultZone] si [hasDefaultCase] est actif).
  String? resolveZoneForValue(String? boundValue) {
    final trimmed = boundValue?.trim();
    if (trimmed != null && trimmed.isNotEmpty && cases.contains(trimmed)) {
      return caseZoneFor(trimmed);
    }
    if (trimmed == null || trimmed.isEmpty) {
      final init = initialCase.trim();
      if (init.isNotEmpty) {
        if (init == defaultZone && hasDefaultCase) return defaultZone;
        if (cases.contains(init)) return caseZoneFor(init);
      }
    }
    if (hasDefaultCase) return defaultZone;
    return null;
  }

  List<String> slotsOf(String zone) => placements[zone] ?? const [];
  String slotTypeOf(String id) => slotTypes[id] ?? id;
  Axis? zoneAxisOf(String zone) => zoneAxes[zone];
  ZoneFlowConfig zoneFlowOf(String zone) =>
      zoneFlows[zone] ?? const ZoneFlowConfig();

  Set<String> get placedSlotIds => {
    for (final ids in placements.values) ...ids,
  };

  /// Tous les slots qui seraient retirés si le cas [caseValue] est supprimé.
  Set<String> slotsRemovedWithCase(String caseValue) =>
      slotsOf(caseZoneFor(caseValue)).toSet();

  SuperConditionalConfig copyWith({
    JsonTextBinding? binding,
    bool clearBinding = false,
    List<String>? cases,
    bool? hasDefaultCase,
    String? initialCase,
    bool? maintainState,
    String? emptyText,
    Map<String, List<String>>? placements,
    Map<String, String>? slotTypes,
    Map<String, Axis>? zoneAxes,
    Map<String, ZoneFlowConfig>? zoneFlows,
    Map<String, Size?>? slotPreferredSizes,
    Map<String, SlotSizeConstraints>? slotSizeConstraints,
    Map<String, String>? slotLabels,
  }) => SuperConditionalConfig(
    binding: clearBinding ? null : binding ?? this.binding,
    cases: cases ?? this.cases,
    hasDefaultCase: hasDefaultCase ?? this.hasDefaultCase,
    initialCase: initialCase ?? this.initialCase,
    maintainState: maintainState ?? this.maintainState,
    emptyText: emptyText ?? this.emptyText,
    placements: placements ?? this.placements,
    slotTypes: slotTypes ?? this.slotTypes,
    zoneAxes: zoneAxes ?? this.zoneAxes,
    zoneFlows: zoneFlows ?? this.zoneFlows,
    slotPreferredSizes: slotPreferredSizes ?? this.slotPreferredSizes,
    slotSizeConstraints: slotSizeConstraints ?? this.slotSizeConstraints,
    slotLabels: slotLabels ?? this.slotLabels,
  );

  /// Ajoute un nouveau cas nommé [caseValue] s'il n'existe pas déjà.
  SuperConditionalConfig withCaseAdded(String caseValue) {
    final trimmed = caseValue.trim();
    if (trimmed.isEmpty || cases.contains(trimmed)) return this;
    return copyWith(cases: [...cases, trimmed]);
  }

  /// Supprime le cas [caseValue] ainsi que sa zone et ses slots associés.
  SuperConditionalConfig withoutCase(String caseValue) {
    final trimmed = caseValue.trim();
    if (!cases.contains(trimmed)) return this;
    final zone = caseZoneFor(trimmed);
    final removedIds = slotsRemovedWithCase(trimmed);
    final next = JsonReader.removeSlotsFromMaps(
      removedIds: removedIds,
      removedZone: zone,
      placements: placements,
      slotTypes: slotTypes,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    );
    return copyWith(
      cases: cases.where((c) => c != trimmed).toList(),
      initialCase: initialCase == trimmed ? '' : initialCase,
      placements: next.placements,
      slotTypes: next.slotTypes,
      zoneAxes: {...zoneAxes}..remove(zone),
      zoneFlows: {...zoneFlows}..remove(zone),
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  /// Renomme un cas existant [oldCase] en [newCase] en préservant ses placements.
  SuperConditionalConfig withCaseRenamed(String oldCase, String newCase) {
    final oldTrimmed = oldCase.trim();
    final newTrimmed = newCase.trim();
    if (oldTrimmed.isEmpty ||
        newTrimmed.isEmpty ||
        oldTrimmed == newTrimmed ||
        !cases.contains(oldTrimmed) ||
        cases.contains(newTrimmed)) {
      return this;
    }
    final oldZone = caseZoneFor(oldTrimmed);
    final newZone = caseZoneFor(newTrimmed);
    String remapZone(String z) => z == oldZone ? newZone : z;
    return copyWith(
      cases: [for (final c in cases) c == oldTrimmed ? newTrimmed : c],
      initialCase: initialCase == oldTrimmed ? newTrimmed : initialCase,
      placements: {
        for (final entry in placements.entries)
          remapZone(entry.key): entry.value,
      },
      zoneAxes: {
        for (final entry in zoneAxes.entries) remapZone(entry.key): entry.value,
      },
      zoneFlows: {
        for (final entry in zoneFlows.entries)
          remapZone(entry.key): entry.value,
      },
    );
  }

  SuperConditionalConfig withSlotAdded(
    String id,
    String zone, {
    String? type,
    bool replace = false,
  }) {
    final next = JsonReader.addSlotToMaps(
      id: id,
      zone: zone,
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
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperConditionalConfig withoutSlot(String id) {
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
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperConditionalConfig withSlotMoved(
    String id,
    String zone, {
    String? beforeId,
    String? afterId,
  }) {
    final next = JsonReader.moveSlotInPlacements(
      id: id,
      zone: zone,
      beforeId: beforeId,
      afterId: afterId,
      placements: placements,
      unknownError: 'Unknown SuperConditional slot.',
      destinationError: 'Invalid SuperConditional slot destination.',
    );
    return next == null ? this : copyWith(placements: next);
  }

  SuperConditionalConfig withSlotReplaced(
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
      zoneAxes: zoneAxes,
      zoneFlows: zoneFlows,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
      errorMessage: 'Invalid SuperConditional slot replacement.',
    );
    return copyWith(
      placements: next.placements,
      slotTypes: next.slotTypes,
      zoneAxes: next.zoneAxes,
      zoneFlows: next.zoneFlows,
      slotPreferredSizes: next.slotPreferredSizes,
      slotSizeConstraints: next.slotSizeConstraints,
      slotLabels: next.slotLabels,
    );
  }

  SuperConditionalConfig withZoneAxis(
    String zone,
    Axis? axis, {
    Axis? defaultAxis,
  }) => copyWith(
    zoneAxes: JsonReader.updateZoneAxisMap(
      zoneAxes,
      zone,
      axis,
      defaultAxis: defaultAxis,
    ),
  );

  SuperConditionalConfig withZoneFlow(String zone, ZoneFlowConfig flow) =>
      copyWith(zoneFlows: JsonReader.updateZoneFlowMap(zoneFlows, zone, flow));

  SuperConditionalConfig withSlotSize(String id, Size? size) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes, id: size},
    slotSizeConstraints: {...slotSizeConstraints}..remove(id),
  );

  SuperConditionalConfig withSlotSizeConstraints(
    String id,
    SlotSizeConstraints constraints,
  ) => copyWith(
    slotPreferredSizes: {...slotPreferredSizes}..remove(id),
    slotSizeConstraints: {...slotSizeConstraints, id: constraints},
  );

  SuperConditionalConfig withSlotLabel(String id, String? label) => copyWith(
    slotLabels: {...slotLabels}
      ..remove(id)
      ..addAll({id: ?label}),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      if (binding != null) 'binding': binding!.toJson(),
      'cases': cases,
      'hasDefaultCase': hasDefaultCase,
      if (initialCase.isNotEmpty) 'initialCase': initialCase,
      'maintainState': maintainState,
      if (emptyText.isNotEmpty) 'emptyText': emptyText,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
        alwaysIncludePlacements: true,
        useShortTypeNameInFullJson: false,
        allowBareSlotIdInFullJson: false,
      ),
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    final d = SuperConditionalConfig();
    return {
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (!listEquals(cases, d.cases)) 'cases': cases,
      if (hasDefaultCase != d.hasDefaultCase) 'hasDefaultCase': hasDefaultCase,
      if (initialCase != d.initialCase) 'initialCase': initialCase,
      if (maintainState != d.maintainState) 'maintainState': maintainState,
      if (emptyText != d.emptyText) 'emptyText': emptyText,
      ...JsonReader.encodeSlotContainerJson(
        placements: placements,
        slotTypeOf: slotTypeOf,
        zoneAxes: zoneAxes,
        zoneFlows: zoneFlows,
        slotPreferredSizes: slotPreferredSizes,
        slotSizeConstraints: slotSizeConstraints,
        slotLabels: slotLabels,
        compact: true,
      ),
    };
  }

  @override
  SuperConditionalConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperConditionalConfig.fromJson({...toJson(), ...patch});

  factory SuperConditionalConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Configuration conditionnelle invalide.');
    }
    final binding = value.containsKey('binding') && value['binding'] != null
        ? JsonTextBinding.fromJson(value['binding'])
        : null;
    final rawCases = value['cases'];
    final cases = <String>[];
    if (rawCases != null) {
      if (rawCases is! List) {
        throw const FormatException('Liste de cas conditionnels invalide.');
      }
      for (final item in rawCases) {
        if (item is! String || item.trim().isEmpty) {
          throw const FormatException('Nom de cas conditionnel invalide.');
        }
        cases.add(item.trim());
      }
    }
    final hasDefaultCase = value['hasDefaultCase'] ?? true;
    final initialCase = value['initialCase'] ?? '';
    final maintainState = value['maintainState'] ?? false;
    final emptyText = value['emptyText'] ?? '';
    if (hasDefaultCase is! bool ||
        initialCase is! String ||
        maintainState is! bool ||
        emptyText is! String) {
      throw const FormatException('Options de SuperConditional invalides.');
    }

    final (:placements, :slotTypes) = JsonReader.parseSlotPlacements(
      value['placements'],
      invalidPlacementsMessage: 'Placements de SuperConditional invalides.',
      invalidZoneMessage: 'Zone de SuperConditional invalide.',
      invalidSlotMessage: 'Slot de SuperConditional invalide.',
    );

    try {
      final meta = JsonReader.parseSlotContainerMetadata(
        value,
        placedIds: placements.values.expand((ids) => ids),
        invalidMetadataMessage:
            'Métadonnées de slots de SuperConditional invalides.',
        invalidLabelsMessage:
            'Libellés de slots de SuperConditional invalides.',
        invalidAxisMessage: 'Axe de zone de SuperConditional invalide.',
        invalidFlowMessage: 'Flux de zone de SuperConditional invalide.',
        invalidConstraintMessage:
            'Contrainte de slot de SuperConditional invalide.',
        invalidSizeMessage: 'Taille de slot de SuperConditional invalide.',
      );
      return SuperConditionalConfig(
        binding: binding,
        cases: cases,
        hasDefaultCase: hasDefaultCase,
        initialCase: initialCase,
        maintainState: maintainState,
        emptyText: emptyText,
        placements: placements,
        slotTypes: slotTypes,
        zoneAxes: meta.zoneAxes,
        zoneFlows: meta.zoneFlows,
        slotPreferredSizes: meta.slotPreferredSizes,
        slotSizeConstraints: meta.slotSizeConstraints,
        slotLabels: meta.slotLabels,
      )..validate();
    } on ArgumentError {
      throw const FormatException('Identifiants de zones ou de slots invalides.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SuperConditionalConfig &&
          binding == other.binding &&
          listEquals(cases, other.cases) &&
          hasDefaultCase == other.hasDefaultCase &&
          initialCase == other.initialCase &&
          maintainState == other.maintainState &&
          emptyText == other.emptyText &&
          JsonReader.sameSlotLayoutMetadata(
            placementsA: placements,
            placementsB: other.placements,
            slotTypesA: slotTypes,
            slotTypesB: other.slotTypes,
            zoneAxesA: zoneAxes,
            zoneAxesB: other.zoneAxes,
            zoneFlowsA: zoneFlows,
            zoneFlowsB: other.zoneFlows,
            slotPreferredSizesA: slotPreferredSizes,
            slotPreferredSizesB: other.slotPreferredSizes,
            slotSizeConstraintsA: slotSizeConstraints,
            slotSizeConstraintsB: other.slotSizeConstraints,
            slotLabelsA: slotLabels,
            slotLabelsB: other.slotLabels,
          ));

  @override
  int get hashCode => Object.hashAll([
    binding,
    Object.hashAll(cases),
    hasDefaultCase,
    initialCase,
    maintainState,
    emptyText,
    ...JsonReader.slotLayoutHashParts(
      placements: placements,
      slotTypes: slotTypes,
      zoneAxes: zoneAxes,
      zoneFlows: zoneFlows,
      slotPreferredSizes: slotPreferredSizes,
      slotSizeConstraints: slotSizeConstraints,
      slotLabels: slotLabels,
    ),
  ]);
}

/// Résumé des propriétés d'un [SuperConditionalConfig] pour l'info-bulle du menu contextuel.
String formatSuperConditionalTooltip({
  required String title,
  required SuperConditionalConfig config,
}) {
  final bindingLabel = config.binding == null
      ? 'Aucune'
      : '${config.binding!.repositoryId ?? 'Hérité'} → ${config.binding!.path}';
  final casesLabel = config.cases.isEmpty
      ? 'Aucun cas'
      : config.cases.join(', ');
  return [
    title,
    'Liaison : $bindingLabel',
    [
      'Cas (${config.cases.length}) : $casesLabel',
      if (config.hasDefaultCase) 'Défaut : Activé',
    ].join(' · '),
    if (config.initialCase.isNotEmpty || config.maintainState)
      [
        if (config.initialCase.isNotEmpty)
          'Cas initial : ${config.initialCase}',
        if (config.maintainState) 'Maintenir l’état',
      ].join(' · '),
  ].join('\n');
}
