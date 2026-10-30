import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../models/registry.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../super_app.dart';
import '../../../theme/container_style.dart';
import '../../components/super_layout/super_layout.dart';
import '../history/editor_history.dart';
import '../slots/editable_surface.dart';
import '../slots/editor_slot.dart';
import '../slots/slot_wrapping.dart';
import 'editor_dialog.dart';
import 'editor_dialog_header.dart';

enum ExtractableComponentKind {
  superValue('SuperValue'),
  superAction('SuperAction'),
  surface('Surface');

  const ExtractableComponentKind(this.label);
  final String label;
}

/// Niveau de tolérance pour détecter que plusieurs blocs sont récurrents.
enum RecurrenceSimilarityMode {
  strict('Stricte', 'Mêmes conteneurs, types et clés de sous-composants'),
  structural(
    'Structurelle',
    'Même structure et séquence de composants (recommandé)',
  ),
  flexible(
    'Tolérante',
    'Tolère des écarts de composants ou de zones selon un seuil %',
  );

  const RecurrenceSimilarityMode(this.label, this.description);
  final String label;
  final String description;
}

/// Organisation de l'arborescence JSON générée hors répétitions.
enum JsonExtractHierarchyMode {
  flatWithArrays(
    'À plat + Tableaux',
    'Propriétés simples à plat et tableaux pour les blocs récurrents',
  ),
  nestedContainers(
    'Arborescence complète',
    'Imbrique aussi les conteneurs nommés en sous-objets JSON',
  );

  const JsonExtractHierarchyMode(this.label, this.description);
  final String label;
  final String description;
}

/// Façon d'intégrer le 1er bloc récurrent dans la ligne (`IterableContent`)
/// de la `SuperListView` générée.
enum ListViewTemplateMode {
  preserveBlock(
    'Conserver le bloc',
    'Place le 1er bloc tel quel dans le gabarit de ligne',
  ),
  unwrapContainer(
    'Fusionner conteneur',
    'Fusionne la Card / Layout racine directement avec la ligne IterableContent',
  );

  const ListViewTemplateMode(this.label, this.description);
  final String label;
  final String description;
}

/// Paramètres de détection de blocs récurrents et de génération de `SuperListView`.
@immutable
class JsonExtractRecurrenceOptions {
  const JsonExtractRecurrenceOptions({
    this.detectRecurrences = true,
    this.similarityMode = RecurrenceSimilarityMode.structural,
    this.similarityThreshold = 0.65,
    this.minOccurrences = 2,
    this.contiguousOnly = true,
    this.includeSingleLeafSlots = false,
    this.ignoreContainerType = false,
    this.requireSameZoneStructure = true,
    this.autoSelectDivergentProperties = true,
    this.hierarchyMode = JsonExtractHierarchyMode.flatWithArrays,
    this.autoConvertToListView = true,
    this.templateMode = ListViewTemplateMode.preserveBlock,
  }) : assert(minOccurrences >= 2),
       assert(similarityThreshold >= 0.0 && similarityThreshold <= 1.0);

  final bool detectRecurrences;
  final RecurrenceSimilarityMode similarityMode;
  final double similarityThreshold;
  final int minOccurrences;
  final bool contiguousOnly;
  final bool includeSingleLeafSlots;
  final bool ignoreContainerType;
  final bool requireSameZoneStructure;
  final bool autoSelectDivergentProperties;
  final JsonExtractHierarchyMode hierarchyMode;
  final bool autoConvertToListView;
  final ListViewTemplateMode templateMode;

  JsonExtractRecurrenceOptions copyWith({
    bool? detectRecurrences,
    RecurrenceSimilarityMode? similarityMode,
    double? similarityThreshold,
    int? minOccurrences,
    bool? contiguousOnly,
    bool? includeSingleLeafSlots,
    bool? ignoreContainerType,
    bool? requireSameZoneStructure,
    bool? autoSelectDivergentProperties,
    JsonExtractHierarchyMode? hierarchyMode,
    bool? autoConvertToListView,
    ListViewTemplateMode? templateMode,
  }) => JsonExtractRecurrenceOptions(
    detectRecurrences: detectRecurrences ?? this.detectRecurrences,
    similarityMode: similarityMode ?? this.similarityMode,
    similarityThreshold: similarityThreshold ?? this.similarityThreshold,
    minOccurrences: minOccurrences ?? this.minOccurrences,
    contiguousOnly: contiguousOnly ?? this.contiguousOnly,
    includeSingleLeafSlots:
        includeSingleLeafSlots ?? this.includeSingleLeafSlots,
    ignoreContainerType: ignoreContainerType ?? this.ignoreContainerType,
    requireSameZoneStructure:
        requireSameZoneStructure ?? this.requireSameZoneStructure,
    autoSelectDivergentProperties:
        autoSelectDivergentProperties ?? this.autoSelectDivergentProperties,
    hierarchyMode: hierarchyMode ?? this.hierarchyMode,
    autoConvertToListView: autoConvertToListView ?? this.autoConvertToListView,
    templateMode: templateMode ?? this.templateMode,
  );

  @override
  bool operator ==(Object other) =>
      other is JsonExtractRecurrenceOptions &&
      other.detectRecurrences == detectRecurrences &&
      other.similarityMode == similarityMode &&
      other.similarityThreshold == similarityThreshold &&
      other.minOccurrences == minOccurrences &&
      other.contiguousOnly == contiguousOnly &&
      other.includeSingleLeafSlots == includeSingleLeafSlots &&
      other.ignoreContainerType == ignoreContainerType &&
      other.requireSameZoneStructure == requireSameZoneStructure &&
      other.autoSelectDivergentProperties == autoSelectDivergentProperties &&
      other.hierarchyMode == hierarchyMode &&
      other.autoConvertToListView == autoConvertToListView &&
      other.templateMode == templateMode;

  @override
  int get hashCode => Object.hash(
    detectRecurrences,
    similarityMode,
    similarityThreshold,
    minOccurrences,
    contiguousOnly,
    includeSingleLeafSlots,
    ignoreContainerType,
    requireSameZoneStructure,
    autoSelectDivergentProperties,
    hierarchyMode,
    autoConvertToListView,
    templateMode,
  );
}

class ExtractablePropertyOption {
  const ExtractablePropertyOption({
    required this.id,
    required this.label,
    required this.value,
    this.defaultSelected = false,
  });

  final String id;
  final String label;
  final Object? value;
  final bool defaultSelected;
}

class ExtractableComponentTarget {
  const ExtractableComponentTarget({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.baseJsonKey,
    required this.properties,
    required this.applyBindings,
  });

  final String id;
  final ExtractableComponentKind kind;
  final String displayName;
  final String baseJsonKey;
  final List<ExtractablePropertyOption> properties;
  final void Function(Map<String, JsonTextBinding> bindings) applyBindings;
}

abstract interface class JsonExtractableState {
  String get extractableId;
  ExtractableComponentKind get extractableKind;
  EditorSlotState? get extractableSurface;
  BuildContext get extractableContext;
  bool get isExtractableMounted;
  String get preferredExtractableKey;
  ExtractableComponentTarget buildExtractableTarget(String assignedBaseKey);
}

String sanitizeJsonAttributeKey(String raw) {
  final sanitized = raw
      .trim()
      .replaceAll(RegExp(r'[.\[\]\s?]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? 'item' : sanitized;
}

String _normalizeSlotType(String rawType) {
  var value = rawType.trim();
  while (value.startsWith('registry:')) {
    value = value.substring('registry:'.length);
  }
  if (value.startsWith('factory:')) {
    value = value.substring('factory:'.length);
  } else if (value.startsWith('component:')) {
    value = value.substring('component:'.length);
  }
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

/// Strips trailing numbering such as `_1`, `_2`, ` 1`, `-2` to compare semantic roles.
String _stripTrailingIndex(String raw) {
  final trimmed = raw.trim();
  final stripped = trimmed.replaceFirst(RegExp(r'[\s_\-#]*\d+$'), '').trim();
  return stripped.isEmpty ? trimmed : stripped;
}

bool _isContainerSlotType(String normalizedType) => const {
  'Card',
  'Layout',
  'Expansible',
  'IterableContent',
  'Tab',
  'Menu',
  'ApplicationBar',
  'BottomAppBar',
  'NavigationRail',
}.contains(normalizedType);

/// Descripteur d'un composant extractible à l'intérieur d'un [ExtractableSlotNode].
class ExtractableSlotTargetEntry {
  const ExtractableSlotTargetEntry({
    required this.state,
    required this.target,
    required this.relativeZonePath,
    required this.hasCustomLabel,
    required this.normalizedRoleKey,
  });

  final JsonExtractableState state;
  final ExtractableComponentTarget target;
  final String relativeZonePath;
  final bool hasCustomLabel;
  final String normalizedRoleKey;
}

/// Représente un bloc candidat placé dans une zone d'un [SuperLayout].
class ExtractableSlotNode {
  const ExtractableSlotNode({
    required this.slotId,
    required this.rawSlotType,
    required this.normalizedSlotType,
    required this.displayLabel,
    required this.customLabel,
    required this.isCompositeBlock,
    required this.containerSignature,
    required this.entries,
    required this.allSurfaces,
    this.preferredSize,
    this.sizeConstraints,
    this.measuredSize,
    this.nestedGroups = const [],
  });

  final String slotId;
  final String rawSlotType;
  final String normalizedSlotType;
  final String displayLabel;
  final String? customLabel;
  final bool isCompositeBlock;
  final String containerSignature;
  final List<ExtractableSlotTargetEntry> entries;
  final List<EditableSurfaceState> allSurfaces;
  final Size? preferredSize;
  final SlotSizeConstraints? sizeConstraints;
  final Size? measuredSize;
  final List<DetectedRecurringBlockGroup> nestedGroups;

  List<ExtractableComponentTarget> get targets => [
    for (final entry in entries) entry.target,
  ];

  /// Core entries excluding optional surface backgrounds when value/action
  /// components exist, so a Card with an image matches a Card without one.
  List<ExtractableSlotTargetEntry> get coreEntries {
    final nonSurface = [
      for (final entry in entries)
        if (entry.target.kind != ExtractableComponentKind.surface) entry,
    ];
    return nonSurface.isNotEmpty ? nonSurface : entries;
  }
}

/// Champ aligné à travers toutes les occurrences d'un [DetectedRecurringBlockGroup].
class AlignedRecurringField {
  const AlignedRecurringField({
    required this.fieldId,
    required this.fieldKey,
    required this.displayName,
    required this.kind,
    required this.properties,
    required this.divergentPropertyIds,
    required this.occurrenceTargets,
    required this.occurrenceValues,
  });

  final String fieldId;
  final String fieldKey;
  final String displayName;
  final ExtractableComponentKind kind;
  final List<ExtractablePropertyOption> properties;
  final Set<String> divergentPropertyIds;

  /// Cible correspondante dans chaque occurrence (index `0 .. occurrences.length - 1`).
  final List<ExtractableComponentTarget?> occurrenceTargets;

  /// Valeurs par propriété pour chaque occurrence.
  final List<Map<String, Object?>> occurrenceValues;

  ExtractableComponentTarget? get templateTarget =>
      occurrenceTargets.firstOrNull;
}

/// Séquence de blocs récurrents détectée dans une zone de [SuperLayout].
class DetectedRecurringBlockGroup {
  const DetectedRecurringBlockGroup({
    required this.id,
    required this.layoutState,
    required this.displayZone,
    required this.contentZone,
    required this.occurrences,
    required this.similarityScore,
    required this.defaultArrayKey,
    required this.blockDisplayName,
    required this.fields,
    required this.inferredAxis,
    required this.inferredSpacing,
    required this.inferredItemExtent,
    required this.inferredItemWidth,
    this.containerPath = const [],
    this.isNestedInList = false,
  });

  final String id;
  final SuperLayoutState layoutState;
  final SuperLayoutZone displayZone;
  final SuperLayoutZone contentZone;
  final List<ExtractableSlotNode> occurrences;
  final double similarityScore;
  final String defaultArrayKey;
  final String blockDisplayName;
  final List<AlignedRecurringField> fields;
  final Axis inferredAxis;
  final double inferredSpacing;
  final double inferredItemExtent;
  final double inferredItemWidth;
  final List<String> containerPath;
  final bool isNestedInList;

  bool get canUnwrapContainer {
    if (occurrences.isEmpty) return false;
    final first = occurrences.first;
    return first.normalizedSlotType == 'Card' ||
        first.normalizedSlotType == 'Layout';
  }

  Set<(ExtractableComponentKind, String)> get coveredTargetKeys => {
    for (final occ in occurrences)
      for (final entry in occ.entries) (entry.target.kind, entry.target.id),
    for (final field in fields)
      for (final target in field.occurrenceTargets)
        if (target != null) (target.kind, target.id),
  };
}

/// Réglages interactifs choisis par l'utilisateur pour un [DetectedRecurringBlockGroup].
class RecurringGroupUserConfig {
  const RecurringGroupUserConfig({
    required this.enabled,
    required this.convertToListView,
    required this.arrayKey,
    required this.axis,
    this.wrap = false,
    this.allowAdd = false,
    this.allowRemove = false,
    this.templateMode = ListViewTemplateMode.preserveBlock,
  });

  final bool enabled;
  final bool convertToListView;
  final String arrayKey;
  final Axis axis;
  final bool wrap;
  final bool allowAdd;
  final bool allowRemove;
  final ListViewTemplateMode templateMode;

  RecurringGroupUserConfig copyWith({
    bool? enabled,
    bool? convertToListView,
    String? arrayKey,
    Axis? axis,
    bool? wrap,
    bool? allowAdd,
    bool? allowRemove,
    ListViewTemplateMode? templateMode,
  }) => RecurringGroupUserConfig(
    enabled: enabled ?? this.enabled,
    convertToListView: convertToListView ?? this.convertToListView,
    arrayKey: arrayKey ?? this.arrayKey,
    axis: axis ?? this.axis,
    wrap: wrap ?? this.wrap,
    allowAdd: allowAdd ?? this.allowAdd,
    allowRemove: allowRemove ?? this.allowRemove,
    templateMode: templateMode ?? this.templateMode,
  );
}

int _lcsLength<T>(List<T> a, List<T> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final dp = List.generate(
    a.length + 1,
    (_) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
  }
  return dp[a.length][b.length];
}

/// Calcule un score de similarité `[0.0 .. 1.0]` entre deux blocs [a] et [b]
/// selon les tolérances définies dans [options].
double computeBlockSimilarity(
  ExtractableSlotNode a,
  ExtractableSlotNode b, [
  JsonExtractRecurrenceOptions options = const JsonExtractRecurrenceOptions(),
]) {
  final aHasExtractable = a.entries.isNotEmpty || a.allSurfaces.isNotEmpty;
  final bHasExtractable = b.entries.isNotEmpty || b.allSurfaces.isNotEmpty;
  if (!aHasExtractable || !bHasExtractable) return 0.0;
  if (a.entries.isEmpty && b.entries.isEmpty) return 0.0;

  if ((!a.isCompositeBlock || !b.isCompositeBlock) &&
      !options.includeSingleLeafSlots) {
    return 0.0;
  }

  final sameContainerType = a.normalizedSlotType == b.normalizedSlotType;
  if (!options.ignoreContainerType && !sameContainerType) {
    return 0.0;
  }

  final coreA = a.coreEntries;
  final coreB = b.coreEntries;
  if (coreA.isEmpty || coreB.isEmpty) return 0.0;

  switch (options.similarityMode) {
    case RecurrenceSimilarityMode.strict:
      if (!sameContainerType) return 0.0;
      if (a.containerSignature != b.containerSignature) return 0.0;
      if (a.entries.length != b.entries.length) return 0.0;
      for (var i = 0; i < a.entries.length; i++) {
        final ea = a.entries[i];
        final eb = b.entries[i];
        if (ea.target.kind != eb.target.kind) return 0.0;
        if (options.requireSameZoneStructure &&
            ea.relativeZonePath != eb.relativeZonePath) {
          return 0.0;
        }
        if (ea.normalizedRoleKey != eb.normalizedRoleKey) {
          return 0.0;
        }
      }
      return 1.0;

    case RecurrenceSimilarityMode.structural:
      if (coreA.length != coreB.length) return 0.0;
      for (var i = 0; i < coreA.length; i++) {
        final ea = coreA[i];
        final eb = coreB[i];
        if (ea.target.kind != eb.target.kind) return 0.0;
        if (options.requireSameZoneStructure &&
            ea.relativeZonePath != eb.relativeZonePath) {
          return 0.0;
        }
      }
      var score = 1.0;
      if (!sameContainerType) score -= 0.1;
      if (a.entries.length != b.entries.length) score -= 0.05;
      return score.clamp(0.0, 1.0);

    case RecurrenceSimilarityMode.flexible:
      final kindsA = [for (final e in coreA) e.target.kind];
      final kindsB = [for (final e in coreB) e.target.kind];
      final lcsKinds = _lcsLength(kindsA, kindsB);
      final kindScore = (2.0 * lcsKinds) / (kindsA.length + kindsB.length);
      if (kindScore == 0) return 0.0;

      final containerScore = sameContainerType
          ? (a.containerSignature == b.containerSignature ? 1.0 : 0.75)
          : 0.5;

      final zonesA = [
        for (final e in coreA) '${e.target.kind.name}@${e.relativeZonePath}',
      ];
      final zonesB = [
        for (final e in coreB) '${e.target.kind.name}@${e.relativeZonePath}',
      ];
      final zoneLcs = _lcsLength(zonesA, zonesB);
      final zoneScore = options.requireSameZoneStructure
          ? (2.0 * zoneLcs) / (zonesA.length + zonesB.length)
          : 1.0;

      final rolesA = {
        for (final e in coreA) '${e.target.kind.name}:${e.normalizedRoleKey}',
      };
      final rolesB = {
        for (final e in coreB) '${e.target.kind.name}:${e.normalizedRoleKey}',
      };
      final unionLen = rolesA.union(rolesB).length;
      final roleScore = unionLen == 0
          ? 1.0
          : rolesA.intersection(rolesB).length / unionLen;

      final total =
          (kindScore * 0.55) +
          (containerScore * 0.20) +
          (zoneScore * 0.15) +
          (roleScore * 0.10);
      return total.clamp(0.0, 1.0);
  }
}

/// Collects all extractable `SuperValue` and `SuperAction` components owned by
/// [slot] or mounted inside [slot]'s subtree.
List<ExtractableComponentTarget> collectExtractableTargetsFromSlot(
  EditorSlotState slot,
) {
  if (!slot.mounted) return const [];
  final statesByKey =
      <(ExtractableComponentKind, String), JsonExtractableState>{};

  JsonExtractableState? direct;
  slot.context.visitAncestorElements((element) {
    if (element is StatefulElement && element.state is JsonExtractableState) {
      final candidate = element.state as JsonExtractableState;
      if (candidate.isExtractableMounted &&
          identical(candidate.extractableSurface, slot)) {
        direct = candidate;
        return false;
      }
    }
    return true;
  });

  void addState(JsonExtractableState state) {
    if (!state.isExtractableMounted) return;
    final mapKey = (state.extractableKind, state.extractableId);
    final existing = statesByKey[mapKey];
    final scope = JsonListScope.maybeOf(state.extractableContext);
    final isPlaceholder = scope?.placeholder ?? false;
    final isSelected = scope?.selected ?? false;
    if (existing == null) {
      statesByKey[mapKey] = state;
    } else {
      final existingScope = JsonListScope.maybeOf(existing.extractableContext);
      final existingPlaceholder = existingScope?.placeholder ?? false;
      final existingSelected = existingScope?.selected ?? false;
      if ((existingPlaceholder && !isPlaceholder) ||
          (!existingSelected && isSelected && !isPlaceholder)) {
        statesByKey[mapKey] = state;
      }
    }
  }

  void visit(Element element) {
    if (element is StatefulElement && element.state is JsonExtractableState) {
      final state = element.state as JsonExtractableState;
      addState(state);
      if (state.extractableKind != ExtractableComponentKind.surface) {
        return;
      }
    }
    element.visitChildren(visit);
  }

  if (direct != null) {
    addState(direct!);
    if (direct!.extractableKind == ExtractableComponentKind.surface) {
      slot.context.visitChildElements(visit);
    }
  } else {
    slot.context.visitChildElements(visit);
  }

  if (statesByKey.isEmpty) return const [];
  final usedKeys = <String>{};
  final targets = <ExtractableComponentTarget>[];
  for (final state in statesByKey.values) {
    final baseKey = sanitizeJsonAttributeKey(state.preferredExtractableKey);
    var uniqueKey = baseKey;
    var suffix = 2;
    while (!usedKeys.add(uniqueKey)) {
      uniqueKey = '${baseKey}_$suffix';
      suffix++;
    }
    final target = state.buildExtractableTarget(uniqueKey);
    if (target.properties.isNotEmpty) {
      targets.add(target);
    }
  }
  return targets;
}

ExtractableSlotNode _buildSlotNode({
  required SuperLayoutState layoutState,
  required String slotId,
  required String displayLabel,
  required List<String> parentContainerPath,
  required JsonExtractRecurrenceOptions options,
}) {
  final config = layoutState.config;
  final rawType = config.slotTypeOf(slotId);
  final normalizedType = _normalizeSlotType(rawType);
  final customLabel = config.slotLabels[slotId];
  final preferredSize = config.slotPreferredSizes[slotId];
  final sizeConstraints = config.slotSizeConstraints[slotId];
  final slotCtx = layoutState.slotContextOf(slotId);

  Size? measuredSize;
  if (slotCtx != null && slotCtx.mounted) {
    final renderObj = slotCtx.findRenderObject();
    if (renderObj is RenderBox && renderObj.hasSize) {
      measuredSize = renderObj.size;
    }
  }

  final statesWithZone = <(JsonExtractableState, String)>[];
  final seenStateKeys = <(ExtractableComponentKind, String), int>{};
  final allSurfaces = <EditableSurfaceState>[];
  final containerTokens = <String>[normalizedType];
  var hasNestedLayoutOrSurface = false;

  void recordState(JsonExtractableState state, List<String> zoneTrail) {
    if (!state.isExtractableMounted) return;
    final key = (state.extractableKind, state.extractableId);
    final relZone = zoneTrail.join('/');
    final existingIdx = seenStateKeys[key];
    final scope = JsonListScope.maybeOf(state.extractableContext);
    final isPlaceholder = scope?.placeholder ?? false;
    final isSelected = scope?.selected ?? false;
    if (existingIdx == null) {
      seenStateKeys[key] = statesWithZone.length;
      statesWithZone.add((state, relZone));
    } else {
      final existing = statesWithZone[existingIdx].$1;
      final existingScope = JsonListScope.maybeOf(existing.extractableContext);
      final existingPlaceholder = existingScope?.placeholder ?? false;
      final existingSelected = existingScope?.selected ?? false;
      if ((existingPlaceholder && !isPlaceholder) ||
          (!existingSelected && isSelected && !isPlaceholder)) {
        statesWithZone[existingIdx] = (state, relZone);
      }
    }
  }

  void walkElement(Element element, List<String> zoneTrail) {
    if (element is StatefulElement) {
      final st = element.state;
      if (st is SuperLayoutState) {
        hasNestedLayoutOrSurface = true;
        final activeZones = [
          for (final z in st.config.visibleZones)
            if (st.slotsInZone(st.config.contentZone(z)).isNotEmpty) z.name,
        ];
        containerTokens.add('Layout(${activeZones.join(",")})');
        for (final z in st.config.visibleZones) {
          final cz = st.config.contentZone(z);
          final slots = st.slotsInZone(cz);
          for (final childSlot in slots) {
            final childCtx = st.slotContextOf(childSlot.id);
            if (childCtx is Element && childCtx.mounted) {
              walkElement(childCtx, [...zoneTrail, cz.name]);
            }
          }
        }
        return;
      }
      if (st is EditableSurfaceState && st.mounted) {
        hasNestedLayoutOrSurface = true;
        if (!allSurfaces.contains(st)) {
          allSurfaces.add(st);
        }
      }
      if (st case final JsonExtractableState extractable) {
        recordState(extractable, zoneTrail);
        if (extractable.extractableKind != ExtractableComponentKind.surface) {
          return;
        }
      }
    }
    element.visitChildren((child) => walkElement(child, zoneTrail));
  }

  if (slotCtx is Element && slotCtx.mounted) {
    walkElement(slotCtx, const []);
  }

  final usedKeys = <String>{};
  final entries = <ExtractableSlotTargetEntry>[];
  for (final (state, relZone) in statesWithZone) {
    final rawPref = state.preferredExtractableKey;
    final baseKey = sanitizeJsonAttributeKey(rawPref);
    var uniqueKey = baseKey;
    var suffix = 2;
    while (!usedKeys.add(uniqueKey)) {
      uniqueKey = '${baseKey}_$suffix';
      suffix++;
    }
    final target = state.buildExtractableTarget(uniqueKey);
    if (target.properties.isEmpty) continue;
    final hasCustom = state.extractableSurface?.hasCustomLabel ?? false;
    final normalizedRole = rawPref == state.extractableId
        ? state.extractableKind.name
        : sanitizeJsonAttributeKey(_stripTrailingIndex(rawPref)).toLowerCase();
    entries.add(
      ExtractableSlotTargetEntry(
        state: state,
        target: target,
        relativeZonePath: relZone,
        hasCustomLabel: hasCustom,
        normalizedRoleKey: normalizedRole,
      ),
    );
  }

  final isComposite =
      _isContainerSlotType(normalizedType) ||
      hasNestedLayoutOrSurface ||
      entries.length >= 2;

  return ExtractableSlotNode(
    slotId: slotId,
    rawSlotType: rawType,
    normalizedSlotType: normalizedType,
    displayLabel: displayLabel,
    customLabel: customLabel,
    isCompositeBlock: isComposite,
    containerSignature: containerTokens.join(' > '),
    entries: entries,
    allSurfaces: allSurfaces,
    preferredSize: preferredSize,
    sizeConstraints: sizeConstraints,
    measuredSize: measuredSize,
  );
}

List<AlignedRecurringField> _alignGroupFields(
  List<ExtractableSlotNode> occurrences,
  JsonExtractRecurrenceOptions options,
) {
  if (occurrences.isEmpty) return const [];
  final n = occurrences.length;

  // Check if any occurrence has a surface imageUrl while others had empty imageUrl
  final anyHasSurfaceTarget = occurrences.any(
    (occ) => occ.entries.any(
      (e) => e.target.kind == ExtractableComponentKind.surface,
    ),
  );
  final effectiveEntriesByOcc = <List<ExtractableSlotTargetEntry>>[];
  for (final occ in occurrences) {
    final list = List<ExtractableSlotTargetEntry>.of(occ.entries);
    if (anyHasSurfaceTarget &&
        !list.any((e) => e.target.kind == ExtractableComponentKind.surface) &&
        occ.allSurfaces.isNotEmpty) {
      final surfaceState = occ.allSurfaces.first;
      final baseTarget = surfaceState.buildExtractableTarget(
        sanitizeJsonAttributeKey(surfaceState.preferredExtractableKey),
      );
      final synthesizedTarget = ExtractableComponentTarget(
        id: baseTarget.id,
        kind: ExtractableComponentKind.surface,
        displayName: baseTarget.displayName,
        baseJsonKey: baseTarget.baseJsonKey,
        properties: baseTarget.properties.isNotEmpty
            ? baseTarget.properties
            : [
                ExtractablePropertyOption(
                  id: ContainerStyleProperty.imageUrl.name,
                  label: 'Image de fond',
                  value: '',
                  defaultSelected: true,
                ),
              ],
        applyBindings: baseTarget.applyBindings,
      );
      list.insert(
        0,
        ExtractableSlotTargetEntry(
          state: surfaceState,
          target: synthesizedTarget,
          relativeZonePath: '',
          hasCustomLabel:
              surfaceState.extractableSurface?.hasCustomLabel ?? false,
          normalizedRoleKey: 'surface',
        ),
      );
    }
    effectiveEntriesByOcc.add(list);
  }

  // Build aligned slots using occurrence 0 as primary backbone, plus any extra
  // entries from other occurrences in flexible mode.
  final firstEntries = effectiveEntriesByOcc.first;
  final alignedRows = <List<ExtractableSlotTargetEntry?>>[];
  final usedIndicesPerOcc = List.generate(n, (_) => <int>{});

  for (var idx0 = 0; idx0 < firstEntries.length; idx0++) {
    final refEntry = firstEntries[idx0];
    final row = List<ExtractableSlotTargetEntry?>.filled(n, null);
    row[0] = refEntry;
    usedIndicesPerOcc[0].add(idx0);

    for (var occIdx = 1; occIdx < n; occIdx++) {
      final candidates = effectiveEntriesByOcc[occIdx];
      final used = usedIndicesPerOcc[occIdx];
      int? bestMatch;

      // 1. Exact kind + same relative zone + same role key
      for (var c = 0; c < candidates.length; c++) {
        if (used.contains(c)) continue;
        final cand = candidates[c];
        if (cand.target.kind == refEntry.target.kind &&
            cand.relativeZonePath == refEntry.relativeZonePath &&
            cand.normalizedRoleKey == refEntry.normalizedRoleKey) {
          bestMatch = c;
          break;
        }
      }
      // 2. Exact kind + same relative zone in order
      if (bestMatch == null) {
        for (var c = 0; c < candidates.length; c++) {
          if (used.contains(c)) continue;
          final cand = candidates[c];
          if (cand.target.kind == refEntry.target.kind &&
              cand.relativeZonePath == refEntry.relativeZonePath) {
            bestMatch = c;
            break;
          }
        }
      }
      // 3. Same kind in order
      if (bestMatch == null) {
        for (var c = 0; c < candidates.length; c++) {
          if (used.contains(c)) continue;
          if (candidates[c].target.kind == refEntry.target.kind) {
            bestMatch = c;
            break;
          }
        }
      }
      if (bestMatch != null) {
        used.add(bestMatch);
        row[occIdx] = candidates[bestMatch];
      }
    }
    alignedRows.add(row);
  }

  // In flexible mode, append any unmatched entries from occurrences 1..n-1
  for (var occIdx = 1; occIdx < n; occIdx++) {
    final candidates = effectiveEntriesByOcc[occIdx];
    final used = usedIndicesPerOcc[occIdx];
    for (var c = 0; c < candidates.length; c++) {
      if (used.contains(c)) continue;
      used.add(c);
      final refEntry = candidates[c];
      final row = List<ExtractableSlotTargetEntry?>.filled(n, null);
      row[occIdx] = refEntry;
      for (var otherIdx = occIdx + 1; otherIdx < n; otherIdx++) {
        final otherCands = effectiveEntriesByOcc[otherIdx];
        final otherUsed = usedIndicesPerOcc[otherIdx];
        for (var oc = 0; oc < otherCands.length; oc++) {
          if (otherUsed.contains(oc)) continue;
          if (otherCands[oc].target.kind == refEntry.target.kind) {
            otherUsed.add(oc);
            row[otherIdx] = otherCands[oc];
            break;
          }
        }
      }
      alignedRows.add(row);
    }
  }

  final usedFieldKeys = <String>{};
  final fields = <AlignedRecurringField>[];

  for (var rowIdx = 0; rowIdx < alignedRows.length; rowIdx++) {
    final row = alignedRows[rowIdx];
    final nonNullEntries = row.whereType<ExtractableSlotTargetEntry>().toList();
    if (nonNullEntries.isEmpty) continue;
    final kind = nonNullEntries.first.target.kind;

    // Derive clean field key inside the array item object
    String? candidateName;
    for (final entry in nonNullEntries) {
      if (entry.hasCustomLabel) {
        candidateName = _stripTrailingIndex(entry.target.displayName);
        break;
      }
    }
    if (candidateName == null) {
      final firstEntry = nonNullEntries.first;
      final rawDisplay = firstEntry.target.displayName.trim();
      final isRawId = rawDisplay == firstEntry.target.id;
      if (!isRawId && rawDisplay.isNotEmpty) {
        final stripped = _stripTrailingIndex(rawDisplay);
        // For SuperAction, if each occurrence has a different button text (e.g. 'Voir', 'Acheter'),
        // the button text is the data value, so prefer a semantic key 'action' unless they share a prefix.
        if (kind == ExtractableComponentKind.superAction) {
          final distinctNames = {
            for (final e in nonNullEntries)
              _stripTrailingIndex(e.target.displayName.trim()).toLowerCase(),
          };
          candidateName = distinctNames.length == 1 ? stripped : 'action';
        } else {
          candidateName = stripped;
        }
      } else {
        candidateName = switch (kind) {
          ExtractableComponentKind.superValue => 'valeur',
          ExtractableComponentKind.superAction => 'action',
          ExtractableComponentKind.surface => 'image',
        };
      }
    }

    final baseFieldKey = sanitizeJsonAttributeKey(candidateName);
    var uniqueFieldKey = baseFieldKey;
    var suffix = 2;
    while (!usedFieldKeys.add(uniqueFieldKey)) {
      uniqueFieldKey = '${baseFieldKey}_$suffix';
      suffix++;
    }

    // Collect union of properties and detect divergent properties across occurrences
    final propOrder = <String>[];
    final propMeta = <String, ExtractablePropertyOption>{};
    final valuesPerProp = <String, List<Object?>>{};

    for (final entry in nonNullEntries) {
      for (final prop in entry.target.properties) {
        if (!propMeta.containsKey(prop.id)) {
          propOrder.add(prop.id);
          propMeta[prop.id] = prop;
        } else if (prop.defaultSelected &&
            !propMeta[prop.id]!.defaultSelected) {
          propMeta[prop.id] = ExtractablePropertyOption(
            id: prop.id,
            label: prop.label,
            value: propMeta[prop.id]!.value,
            defaultSelected: true,
          );
        }
      }
    }

    final occurrenceValues = <Map<String, Object?>>[];
    for (var occIdx = 0; occIdx < n; occIdx++) {
      final entry = row[occIdx];
      final map = <String, Object?>{};
      for (final propId in propOrder) {
        final match = entry?.target.properties
            .where((p) => p.id == propId)
            .firstOrNull;
        final val =
            match?.value ??
            (propId == 'imageUrl' ? '' : propMeta[propId]?.value);
        map[propId] = val;
        valuesPerProp.putIfAbsent(propId, () => []).add(val);
      }
      occurrenceValues.add(map);
    }

    final divergentIds = <String>{};
    for (final entry in valuesPerProp.entries) {
      final distinct = entry.value.map((v) => '$v').toSet();
      if (distinct.length > 1) {
        divergentIds.add(entry.key);
      }
    }

    final mergedProps = <ExtractablePropertyOption>[
      for (final propId in propOrder)
        () {
          final meta = propMeta[propId]!;
          final autoSelect =
              meta.defaultSelected ||
              (options.autoSelectDivergentProperties &&
                  divergentIds.contains(propId));
          return ExtractablePropertyOption(
            id: meta.id,
            label: meta.label,
            value: occurrenceValues.first[propId],
            defaultSelected: autoSelect,
          );
        }(),
    ];

    fields.add(
      AlignedRecurringField(
        fieldId: nonNullEntries.first.target.id,
        fieldKey: uniqueFieldKey,
        displayName: uniqueFieldKey,
        kind: kind,
        properties: mergedProps,
        divergentPropertyIds: divergentIds,
        occurrenceTargets: [for (final e in row) e?.target],
        occurrenceValues: occurrenceValues,
      ),
    );
  }

  return fields;
}

String _inferDefaultArrayKey({
  required List<ExtractableSlotNode> occurrences,
  required SuperLayoutState layoutState,
  required SuperLayoutZone displayZone,
  required Set<String> usedArrayKeys,
}) {
  String? candidate;
  for (final occ in occurrences) {
    if (occ.customLabel != null && occ.customLabel!.trim().isNotEmpty) {
      candidate = _stripTrailingIndex(occ.customLabel!);
      break;
    }
  }
  if (candidate == null || candidate.isEmpty) {
    final layoutLabel = layoutState.displayLabel.trim();
    if (layoutLabel.isNotEmpty &&
        layoutLabel != 'Layout' &&
        layoutLabel != 'Main Layout' &&
        layoutLabel != 'Formulaire') {
      candidate = layoutLabel;
    } else {
      candidate = switch (occurrences.first.normalizedSlotType) {
        'Card' => 'items',
        'Layout' => 'lignes',
        _ => 'elements',
      };
    }
  }
  final base = sanitizeJsonAttributeKey(candidate);
  var unique = base;
  var suffix = 2;
  while (!usedArrayKeys.add(unique)) {
    unique = '${base}_$suffix';
    suffix++;
  }
  return unique;
}

double _inferItemExtent(List<ExtractableSlotNode> occurrences, Axis axis) {
  final first = occurrences.first;
  final constraints = first.sizeConstraints;
  if (axis == Axis.vertical) {
    if (constraints?.preferredHeight case final pref?
        when pref.unit == SlotSizeUnit.pixels) {
      return pref.value.clamp(
        SuperListViewConfig.minItemExtent,
        SuperListViewConfig.maxItemExtent,
      );
    }
    if (first.preferredSize case final size?) {
      return size.height.clamp(
        SuperListViewConfig.minItemExtent,
        SuperListViewConfig.maxItemExtent,
      );
    }
    if (first.measuredSize case final measured? when measured.height >= 16) {
      return measured.height.clamp(
        SuperListViewConfig.minItemExtent,
        SuperListViewConfig.maxItemExtent,
      );
    }
    return 80.0;
  } else {
    if (constraints?.preferredWidth case final pref?
        when pref.unit == SlotSizeUnit.pixels) {
      return pref.value.clamp(
        SuperListViewConfig.minItemExtent,
        SuperListViewConfig.maxItemExtent,
      );
    }
    if (first.preferredSize case final size?) {
      return size.width.clamp(
        SuperListViewConfig.minItemExtent,
        SuperListViewConfig.maxItemExtent,
      );
    }
    if (first.measuredSize case final measured? when measured.width >= 16) {
      return measured.width.clamp(
        SuperListViewConfig.minItemExtent,
        SuperListViewConfig.maxItemExtent,
      );
    }
    return 160.0;
  }
}

/// Détecte les groupes de blocs récurrents dans le sous-arbre de [slot] selon [options].
List<DetectedRecurringBlockGroup> detectRecurringBlockGroups(
  EditorSlotState slot, {
  JsonExtractRecurrenceOptions options = const JsonExtractRecurrenceOptions(),
}) {
  if (!slot.mounted || !options.detectRecurrences) return const [];

  final groups = <DetectedRecurringBlockGroup>[];
  final usedArrayKeys = <String>{};
  final visitedZonePairs = <(SuperLayoutState, SuperLayoutZone)>{};
  final enclosingListScope = JsonListScope.maybeOf(slot.context) != null;

  void analyzeZone(
    SuperLayoutState layoutState,
    SuperLayoutZone displayZone,
    List<String> containerPath,
  ) {
    final contentZone = layoutState.config.contentZone(displayZone);
    if (!visitedZonePairs.add((layoutState, contentZone))) return;

    final placedSlots = layoutState.slotsInZone(contentZone);
    if (placedSlots.length < options.minOccurrences) {
      // Even if this zone has fewer than minOccurrences slots, inspect inside
      // each slot for nested layouts!
      for (final s in placedSlots) {
        final slotCtx = layoutState.slotContextOf(s.id);
        if (slotCtx is Element && slotCtx.mounted) {
          final label = layoutState.config.slotLabels[s.id] ?? s.label;
          final nextPath = [
            ...containerPath,
            if (label.trim().isNotEmpty && label != 'Card' && label != 'Layout')
              sanitizeJsonAttributeKey(label),
          ];
          _visitNestedLayouts(slotCtx, nextPath, analyzeZone);
        }
      }
      return;
    }

    final nodes = <ExtractableSlotNode>[
      for (final s in placedSlots)
        _buildSlotNode(
          layoutState: layoutState,
          slotId: s.id,
          displayLabel: layoutState.config.slotLabels[s.id] ?? s.label,
          parentContainerPath: containerPath,
          options: options,
        ),
    ];

    final effectiveThreshold = switch (options.similarityMode) {
      RecurrenceSimilarityMode.strict => 1.0,
      RecurrenceSimilarityMode.structural => 0.85,
      RecurrenceSimilarityMode.flexible => options.similarityThreshold,
    };

    final runs = <List<(ExtractableSlotNode, double)>>[];
    if (options.contiguousOnly) {
      var i = 0;
      while (i < nodes.length) {
        final seed = nodes[i];
        final currentRun = <(ExtractableSlotNode, double)>[(seed, 1.0)];
        var j = i + 1;
        while (j < nodes.length) {
          final candidate = nodes[j];
          final sim = computeBlockSimilarity(seed, candidate, options);
          if (sim >= effectiveThreshold) {
            currentRun.add((candidate, sim));
            j++;
          } else {
            break;
          }
        }
        if (currentRun.length >= options.minOccurrences) {
          runs.add(currentRun);
          i = j;
        } else {
          i++;
        }
      }
    } else {
      final consumed = <int>{};
      for (var i = 0; i < nodes.length; i++) {
        if (consumed.contains(i)) continue;
        final seed = nodes[i];
        final cluster = <(ExtractableSlotNode, double)>[(seed, 1.0)];
        final clusterIndices = <int>[i];
        for (var j = i + 1; j < nodes.length; j++) {
          if (consumed.contains(j)) continue;
          final candidate = nodes[j];
          final sim = computeBlockSimilarity(seed, candidate, options);
          if (sim >= effectiveThreshold) {
            cluster.add((candidate, sim));
            clusterIndices.add(j);
          }
        }
        if (cluster.length >= options.minOccurrences) {
          consumed.addAll(clusterIndices);
          runs.add(cluster);
        }
      }
    }

    final groupedSlotIds = <String>{};
    for (final run in runs) {
      final occurrences = [for (final item in run) item.$1];
      for (final occ in occurrences) {
        groupedSlotIds.add(occ.slotId);
      }
      final avgSim = run.fold<double>(0.0, (sum, e) => sum + e.$2) / run.length;
      final fields = _alignGroupFields(occurrences, options);
      if (fields.isEmpty) continue;

      final arrayKey = _inferDefaultArrayKey(
        occurrences: occurrences,
        layoutState: layoutState,
        displayZone: displayZone,
        usedArrayKeys: usedArrayKeys,
      );
      final axis = layoutState.config.axisOf(displayZone);
      final spacing = layoutState.config
          .flowOf(displayZone)
          .spacing
          .clamp(0.0, SuperListViewConfig.maxSpacing);
      final itemExtent = _inferItemExtent(occurrences, axis);
      final itemWidth = _inferItemExtent(occurrences, Axis.horizontal);
      final layoutId = layoutState.effectiveLayoutId ?? 'layout';
      final groupId =
          '${layoutId}_${contentZone.name}_${occurrences.first.slotId}';

      groups.add(
        DetectedRecurringBlockGroup(
          id: groupId,
          layoutState: layoutState,
          displayZone: displayZone,
          contentZone: contentZone,
          occurrences: occurrences,
          similarityScore: avgSim,
          defaultArrayKey: arrayKey,
          blockDisplayName: occurrences.first.displayLabel,
          fields: fields,
          inferredAxis: axis,
          inferredSpacing: spacing,
          inferredItemExtent: itemExtent,
          inferredItemWidth: itemWidth,
          containerPath: containerPath,
          isNestedInList: enclosingListScope,
        ),
      );
    }

    // For any slot in this zone that was NOT grouped as a recurring block,
    // recursively inspect nested SuperLayouts inside it.
    for (final s in placedSlots) {
      if (groupedSlotIds.contains(s.id)) continue;
      final slotCtx = layoutState.slotContextOf(s.id);
      if (slotCtx is Element && slotCtx.mounted) {
        final label = layoutState.config.slotLabels[s.id] ?? s.label;
        final nextPath = [
          ...containerPath,
          if (label.trim().isNotEmpty && label != 'Card' && label != 'Layout')
            sanitizeJsonAttributeKey(label),
        ];
        _visitNestedLayouts(slotCtx, nextPath, analyzeZone);
      }
    }
  }

  // Check if [slot] is a zone EditorSlot or the outer EditorSlot of an ancestor SuperLayoutState
  final ancestorLayout = slot.context
      .findAncestorStateOfType<SuperLayoutState>();
  if (ancestorLayout != null && ancestorLayout.mounted) {
    final matchedZone = ancestorLayout.zoneForEditorSlot(slot);
    if (matchedZone != null) {
      analyzeZone(ancestorLayout, matchedZone, const []);
      return groups;
    }
    // Check if [slot] is the outer EditorSlot of [ancestorLayout] itself
    // (i.e. not nested inside one of [ancestorLayout]'s placed child slots).
    final isInsidePlacedChild = ancestorLayout.config.placedSlotIds.any((id) {
      final childCtx = ancestorLayout.slotContextOf(id);
      if (childCtx is! Element || !childCtx.mounted) return false;
      var found = false;
      slot.context.visitAncestorElements((el) {
        if (identical(el, childCtx)) {
          found = true;
          return false;
        }
        if (identical(el, ancestorLayout.context)) return false;
        return true;
      });
      return found;
    });
    if (!isInsidePlacedChild) {
      for (final zone in ancestorLayout.config.visibleZones) {
        analyzeZone(ancestorLayout, zone, const []);
      }
      return groups;
    }
  }

  // Otherwise inspect all top-level SuperLayoutStates inside slot.context
  if (slot.context is Element) {
    _visitNestedLayouts(
      slot.context as Element,
      const [],
      analyzeZone,
      includeSelf: true,
    );
  }

  return groups;
}

void _visitNestedLayouts(
  Element root,
  List<String> containerPath,
  void Function(SuperLayoutState, SuperLayoutZone, List<String>) onZone, {
  bool includeSelf = false,
}) {
  void walk(Element element) {
    if (element is StatefulElement && element.state is SuperLayoutState) {
      final layoutState = element.state as SuperLayoutState;
      if (layoutState.mounted) {
        for (final zone in layoutState.config.visibleZones) {
          onZone(layoutState, zone, containerPath);
        }
      }
      return;
    }
    element.visitChildren(walk);
  }

  if (includeSelf) {
    walk(root);
  } else {
    root.visitChildren(walk);
  }
}

/// Dialog displaying the JSON extracted from `SuperValue`, `SuperAction` and
/// `EditableSurface` components, detecting recurring blocks with configurable
/// similarity tolerances, building JSON arrays/trees, and optionally replacing
/// recurring blocks with an automatically bound `SuperListView`.
class SuperValueJsonExtractDialog extends StatefulWidget {
  const SuperValueJsonExtractDialog({
    this.values = const {},
    this.targets = const [],
    this.ownerContext,
    this.rootSlot,
    this.sourceLabel,
    this.store,
    this.initialRecurrenceOptions = const JsonExtractRecurrenceOptions(),
    super.key,
  });

  final Map<String, Object?> values;
  final List<ExtractableComponentTarget> targets;
  final BuildContext? ownerContext;
  final EditorSlotState? rootSlot;
  final String? sourceLabel;
  final JsonRepositoryStore? store;
  final JsonExtractRecurrenceOptions initialRecurrenceOptions;

  static Future<void> show(
    BuildContext context, {
    Map<String, Object?> values = const {},
    List<ExtractableComponentTarget> targets = const [],
    String? sourceLabel,
    BuildContext? target,
    EditorSlotState? rootSlot,
    JsonExtractRecurrenceOptions initialRecurrenceOptions =
        const JsonExtractRecurrenceOptions(),
  }) {
    final store = JsonRepositoryScope.maybeOf(context);
    EditorSlotState? resolvedSlot = rootSlot;
    if (resolvedSlot == null &&
        context is StatefulElement &&
        context.state is EditorSlotState) {
      resolvedSlot = context.state as EditorSlotState;
    }
    return showEditorDialog<void>(
      context: context,
      target: target,
      builder: (_) => SuperValueJsonExtractDialog(
        values: values,
        targets: targets,
        ownerContext: context,
        rootSlot: resolvedSlot,
        sourceLabel: sourceLabel,
        store: store,
        initialRecurrenceOptions: initialRecurrenceOptions,
      ),
    );
  }

  @override
  State<SuperValueJsonExtractDialog> createState() =>
      _SuperValueJsonExtractDialogState();
}

class _SuperValueJsonExtractDialogState
    extends State<SuperValueJsonExtractDialog> {
  late final TextEditingController _json;
  late final TextEditingController _repoName;
  late final Map<(ExtractableComponentKind, String), Set<String>>
  _selectedProps;
  late JsonExtractRecurrenceOptions _recurrenceOptions;
  List<DetectedRecurringBlockGroup> _detectedGroups = const [];
  final Map<String, RecurringGroupUserConfig> _groupConfigs = {};
  final Map<String, TextEditingController> _groupKeyControllers = {};
  final Map<(String, String), Set<String>> _selectedGroupFieldProps = {};
  bool _showRecurrenceSettings = false;
  JsonRepositoryStore? _ownedStore;
  bool _autoBind = true;
  String? _status;
  String? _error;
  bool _busy = false;

  EditorSlotState? get _effectiveRootSlot {
    if (widget.rootSlot != null && widget.rootSlot!.mounted) {
      return widget.rootSlot;
    }
    final ctx = widget.ownerContext;
    if (ctx is StatefulElement && ctx.mounted && ctx.state is EditorSlotState) {
      return ctx.state as EditorSlotState;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _recurrenceOptions = widget.initialRecurrenceOptions;
    _selectedProps = {
      for (final target in widget.targets)
        (target.kind, target.id): {
          for (final prop in target.properties)
            if (prop.defaultSelected) prop.id,
        },
    };
    _refreshDetectedGroups(initial: true);
    final initialMap = widget.targets.isNotEmpty || _detectedGroups.isNotEmpty
        ? _buildExtractedPayload().json
        : widget.values;
    _json = TextEditingController(
      text: '${const JsonEncoder.withIndent('  ').convert(initialMap)}\n',
    );
    _repoName = TextEditingController(
      text: _defaultRepositoryName(widget.sourceLabel),
    );
  }

  void _refreshDetectedGroups({bool initial = false}) {
    final slot = _effectiveRootSlot;
    if (slot == null) {
      _detectedGroups = const [];
      return;
    }
    final groups = detectRecurringBlockGroups(
      slot,
      options: _recurrenceOptions,
    );
    _detectedGroups = groups;
    for (final group in groups) {
      final previous = _groupConfigs[group.id];
      final effectiveConfig =
          previous?.copyWith(
            convertToListView: initial
                ? _recurrenceOptions.autoConvertToListView
                : previous.convertToListView,
          ) ??
          RecurringGroupUserConfig(
            enabled: true,
            convertToListView: _recurrenceOptions.autoConvertToListView,
            arrayKey: group.defaultArrayKey,
            axis: group.inferredAxis,
            templateMode: _recurrenceOptions.templateMode,
          );
      _groupConfigs[group.id] = effectiveConfig;
      _groupKeyControllers.putIfAbsent(
        group.id,
        () => TextEditingController(text: effectiveConfig.arrayKey),
      );
      for (final field in group.fields) {
        final key = (group.id, field.fieldKey);
        final selectedSet = _selectedGroupFieldProps.putIfAbsent(
          key,
          () => {
            for (final prop in field.properties)
              if (prop.defaultSelected) prop.id,
          },
        );
        if (_recurrenceOptions.autoSelectDivergentProperties) {
          selectedSet.addAll(field.divergentPropertyIds);
        }
        // Keep template target's _selectedProps synchronized
        if (field.templateTarget case final tpl?) {
          _selectedProps[(tpl.kind, tpl.id)] = Set<String>.of(selectedSet);
        }
      }
    }
  }

  void _updateRecurrenceOptions(JsonExtractRecurrenceOptions next) {
    if (next == _recurrenceOptions) return;
    setState(() {
      _status = null;
      _error = null;
      _recurrenceOptions = next;
      _refreshDetectedGroups();
      _syncJsonText();
    });
  }

  void _updateGroupConfig(String groupId, RecurringGroupUserConfig next) {
    setState(() {
      _status = null;
      _error = null;
      _groupConfigs[groupId] = next;
      _syncJsonText();
    });
  }

  void _syncJsonText() {
    final payload = _buildExtractedPayload();
    _json.text =
        '${const JsonEncoder.withIndent('  ').convert(payload.json)}\n';
  }

  void _placeAtContainerPath(
    Map<String, Object?> root,
    List<String> containerPath,
    String key,
    Object? value,
  ) {
    if (_recurrenceOptions.hierarchyMode !=
            JsonExtractHierarchyMode.nestedContainers ||
        containerPath.isEmpty) {
      root[key] = value;
      return;
    }
    var current = root;
    for (final segment in containerPath) {
      final existing = current[segment];
      if (existing is Map<String, Object?>) {
        current = existing;
      } else {
        final created = <String, Object?>{};
        current[segment] = created;
        current = created;
      }
    }
    current[key] = value;
  }

  String _joinJsonPath(List<String> prefix, String leaf) {
    if (_recurrenceOptions.hierarchyMode !=
            JsonExtractHierarchyMode.nestedContainers ||
        prefix.isEmpty) {
      return leaf;
    }
    return '${prefix.join('.')}.$leaf';
  }

  /// Construit le JSON complet (avec tableaux pour les groupes récurrents
  /// actifs) ainsi que les chemins de liaison pour les composants hors liste
  /// et pour les groupes récurrents.
  ({
    Map<String, Object?> json,
    Map<(ExtractableComponentKind, String), Map<String, String>> paths,
    Map<String, String> groupArrayPaths,
    Map<(String, String), Map<String, String>> groupFieldRelativePaths,
  })
  _buildExtractedPayload() {
    final json = <String, Object?>{};
    final paths = <(ExtractableComponentKind, String), Map<String, String>>{};
    final groupArrayPaths = <String, String>{};
    final groupFieldRelativePaths = <(String, String), Map<String, String>>{};

    final activeGroups = [
      for (final group in _detectedGroups)
        if (_groupConfigs[group.id]?.enabled ?? true) group,
    ];
    final coveredByActiveGroups = <(ExtractableComponentKind, String)>{
      for (final group in activeGroups) ...group.coveredTargetKeys,
    };

    // 1. Standalone targets (not part of an active recurring group)
    for (final target in widget.targets) {
      final targetKey = (target.kind, target.id);
      if (coveredByActiveGroups.contains(targetKey)) continue;
      final selectedIds = _selectedProps[targetKey] ?? const {};
      final chosen = [
        for (final prop in target.properties)
          if (selectedIds.contains(prop.id)) prop,
      ];
      if (chosen.isEmpty) continue;
      if (chosen.length == 1) {
        final single = chosen.single;
        json[target.baseJsonKey] = single.value;
        paths[targetKey] = {single.id: target.baseJsonKey};
      } else {
        json[target.baseJsonKey] = {
          for (final prop in chosen) prop.id: prop.value,
        };
        paths[targetKey] = {
          for (final prop in chosen)
            prop.id: '${target.baseJsonKey}.${prop.id}',
        };
      }
    }

    // 2. Active recurring block groups -> JSON arrays
    final usedArrayPaths = <String>{...json.keys};
    for (final group in activeGroups) {
      final cfg = _groupConfigs[group.id]!;
      final rawArrayKey = sanitizeJsonAttributeKey(
        cfg.arrayKey.trim().isEmpty ? group.defaultArrayKey : cfg.arrayKey,
      );
      var arrayKey = rawArrayKey;
      var suffix = 2;
      while (!usedArrayPaths.add(arrayKey)) {
        arrayKey = '${rawArrayKey}_$suffix';
        suffix++;
      }

      final fullArrayPath = _joinJsonPath(group.containerPath, arrayKey);
      groupArrayPaths[group.id] = fullArrayPath;

      final items = <Map<String, Object?>>[];
      for (var occIdx = 0; occIdx < group.occurrences.length; occIdx++) {
        final itemMap = <String, Object?>{};
        for (final field in group.fields) {
          final selectedIds =
              _selectedGroupFieldProps[(group.id, field.fieldKey)] ?? const {};
          final chosen = [
            for (final prop in field.properties)
              if (selectedIds.contains(prop.id)) prop,
          ];
          if (chosen.isEmpty) continue;
          final occValues = field.occurrenceValues[occIdx];
          if (chosen.length == 1) {
            final single = chosen.single;
            itemMap[field.fieldKey] = occValues[single.id];
            if (occIdx == 0) {
              groupFieldRelativePaths[(group.id, field.fieldKey)] = {
                single.id: field.fieldKey,
              };
            }
          } else {
            itemMap[field.fieldKey] = {
              for (final prop in chosen) prop.id: occValues[prop.id],
            };
            if (occIdx == 0) {
              groupFieldRelativePaths[(group.id, field.fieldKey)] = {
                for (final prop in chosen)
                  prop.id: '${field.fieldKey}.${prop.id}',
              };
            }
          }
        }
        items.add(itemMap);
      }

      _placeAtContainerPath(json, group.containerPath, arrayKey, items);
    }

    return (
      json: json,
      paths: paths,
      groupArrayPaths: groupArrayPaths,
      groupFieldRelativePaths: groupFieldRelativePaths,
    );
  }

  void _toggleProperty(
    ExtractableComponentTarget target,
    String propertyId,
    bool selected,
  ) {
    setState(() {
      _status = null;
      _error = null;
      final set = _selectedProps.putIfAbsent((
        target.kind,
        target.id,
      ), () => <String>{});
      if (selected) {
        set.add(propertyId);
      } else {
        set.remove(propertyId);
      }
      _syncJsonText();
    });
  }

  void _toggleGroupFieldProperty(
    DetectedRecurringBlockGroup group,
    AlignedRecurringField field,
    String propertyId,
    bool selected,
  ) {
    setState(() {
      _status = null;
      _error = null;
      final set = _selectedGroupFieldProps.putIfAbsent((
        group.id,
        field.fieldKey,
      ), () => <String>{});
      if (selected) {
        set.add(propertyId);
      } else {
        set.remove(propertyId);
      }
      if (field.templateTarget case final tpl?) {
        _selectedProps[(tpl.kind, tpl.id)] = Set<String>.of(set);
      }
      _syncJsonText();
    });
  }

  static String _defaultRepositoryName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final sanitized = raw
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\.+'), '_');
    return sanitized;
  }

  @override
  void dispose() {
    _ownedStore?.dispose();
    _json.dispose();
    _repoName.dispose();
    for (final ctrl in _groupKeyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _json.text));
    if (!mounted) return;
    setState(() {
      _error = null;
      _status = 'Copié dans le presse-papiers.';
    });
  }

  /// Convertit un [DetectedRecurringBlockGroup] en une `SuperListView` liée à
  /// [arrayPath], conserve et lie la 1re occurrence comme gabarit (`template`),
  /// et supprime les occurrences `1..N-1` de la disposition parente.
  bool _convertGroupToListView({
    required BuildContext ownerContext,
    required DetectedRecurringBlockGroup group,
    required RecurringGroupUserConfig userConfig,
    required String repoId,
    required String arrayPath,
    required Map<(String, String), Map<String, String>> groupFieldRelativePaths,
  }) {
    final layoutState = group.layoutState;
    if (!layoutState.mounted) return false;
    final registry = SuperApp.maybeOf(ownerContext)?.registry;
    if (registry == null) return false;

    final currentParentConfig = layoutState.config;
    final zonePlacements = List<String>.of(
      currentParentConfig.placementsOf(group.contentZone),
    );
    final firstNode = group.occurrences.first;
    if (!zonePlacements.contains(firstNode.slotId)) return false;

    // 1. Apply wildcard `[?]` bindings to the first occurrence (the template)
    Map<String, JsonTextBinding>? outerSurfaceBindings;
    for (final field in group.fields) {
      final relPaths = groupFieldRelativePaths[(group.id, field.fieldKey)];
      if (relPaths == null || relPaths.isEmpty) continue;
      final tplTarget = field.templateTarget;
      if (tplTarget == null) continue;
      final bindings = <String, JsonTextBinding>{
        for (final entry in relPaths.entries)
          entry.key: JsonTextBinding(
            // Inherit repository from the enclosing SuperListView
            repositoryId: null,
            path: '$arrayPath[?].${entry.value}',
          ),
      };
      if (userConfig.templateMode == ListViewTemplateMode.unwrapContainer &&
          tplTarget.kind == ExtractableComponentKind.surface &&
          tplTarget.id == firstNode.slotId) {
        outerSurfaceBindings = bindings;
      } else {
        tplTarget.applyBindings(bindings);
      }
    }

    // 2. Allocate unique ID for the new SuperListView
    final occupiedIds = <String>{
      ...currentParentConfig.placedSlotIds,
      ...registry.instantiatedComponentIds,
    };
    final listId = uniqueInstanceId(
      ownerContext,
      registry: registry,
      occupiedIds: occupiedIds,
    );

    // 3. Build row template layout & style
    SuperLayoutConfig templateLayout;
    ContainerStyle templateStyle = const ContainerStyle();
    String? unwrappedOuterId;

    if (userConfig.templateMode == ListViewTemplateMode.unwrapContainer &&
        group.canUnwrapContainer) {
      if (firstNode.normalizedSlotType == 'Card') {
        final cardNative = registry
            .nativeComponentController(firstNode.slotId)
            .value;
        final childSlots = cardNative.slotsOf('child');
        final singleChildId = childSlots.length == 1 ? childSlots.single : null;
        final singleChildType = singleChildId == null
            ? null
            : _normalizeSlotType(cardNative.slotTypeOf(singleChildId));
        var cardStyle = registry.styleController(firstNode.slotId).value;
        if (outerSurfaceBindings != null && outerSurfaceBindings.isNotEmpty) {
          cardStyle = cardStyle.copyWith(
            propertyBindings: {
              ...cardStyle.propertyBindings,
              for (final prop in ContainerStyleProperty.values)
                prop: ?outerSurfaceBindings[prop.name],
            },
          );
        }
        templateStyle = cardStyle;
        if (singleChildId != null && singleChildType == 'Layout') {
          templateLayout = registry.layoutController(singleChildId).value;
          unwrappedOuterId = firstNode.slotId;
        } else if (singleChildId != null) {
          templateLayout = SuperLayoutConfig(
            placements: {
              SuperLayoutZone.center: [singleChildId],
            },
            slotTypes: {singleChildId: cardNative.slotTypeOf(singleChildId)},
            slotLabels: {
              if (cardNative.slotLabels[singleChildId] case final lbl?)
                singleChildId: lbl,
            },
          );
          unwrappedOuterId = firstNode.slotId;
        } else {
          templateLayout = const SuperLayoutConfig();
          unwrappedOuterId = firstNode.slotId;
        }
      } else if (firstNode.normalizedSlotType == 'Layout') {
        templateLayout = registry.layoutController(firstNode.slotId).value;
        unwrappedOuterId = firstNode.slotId;
      } else {
        templateLayout = SuperLayoutConfig(
          placements: {
            SuperLayoutZone.center: [firstNode.slotId],
          },
          slotTypes: {firstNode.slotId: firstNode.rawSlotType},
          slotLabels: {
            if (firstNode.customLabel != null)
              firstNode.slotId: firstNode.customLabel!,
          },
        );
      }
    } else {
      templateLayout = SuperLayoutConfig(
        placements: {
          SuperLayoutZone.center: [firstNode.slotId],
        },
        slotTypes: {firstNode.slotId: firstNode.rawSlotType},
        slotLabels: {
          if (firstNode.customLabel != null)
            firstNode.slotId: firstNode.customLabel!,
        },
      );
    }

    final zoneFlow = currentParentConfig.flowOf(group.displayZone);
    final listConfig = SuperListViewConfig(
      binding: JsonTextBinding(
        repositoryId: group.isNestedInList ? null : repoId,
        path: arrayPath,
      ),
      axis: userConfig.axis,
      wrap: userConfig.wrap,
      itemExtent: group.inferredItemExtent,
      itemWidth: group.inferredItemWidth,
      spacing: group.inferredSpacing,
      allowAdd: userConfig.allowAdd,
      allowRemove: userConfig.allowRemove,
      showScrollbar: zoneFlow.showScrollbar,
      scrollbarStyle: zoneFlow.scrollbarStyle,
      template: templateLayout,
    );

    registry.styleController(listId).value = templateStyle;
    registry.layoutController(listId).value = templateLayout;
    registry.listController(listId).value = listConfig;

    // 4. Replace occurrences[0] with listId and remove occurrences[1..N-1]
    // in the parent SuperLayoutConfig
    final duplicateIds = {
      for (final occ in group.occurrences.skip(1)) occ.slotId,
    };
    final allReplacedIds = {firstNode.slotId, ...duplicateIds};

    final updatedZonePlacements = <String>[
      for (final id in zonePlacements)
        if (id == firstNode.slotId)
          listId
        else if (!duplicateIds.contains(id))
          id,
    ];

    final otherZoneReferenced = <String>{
      for (final entry in currentParentConfig.placements.entries)
        if (entry.key != group.contentZone) ...entry.value,
    };
    final removedFromParent = allReplacedIds.difference(otherZoneReferenced);

    // Ensure the new ListView gets flex: 1 (fitContent: false) when the zone
    // does not expand slots by default, so it receives a bounded main-axis viewport.
    final listConstraints =
        !zoneFlow.expandSlots ||
            zoneFlow.mainAxisAlignment != MainAxisAlignment.start
        ? const SlotSizeConstraints(fitContent: false)
        : null;

    final nextParentConfig = currentParentConfig.copyWith(
      placements: {
        ...currentParentConfig.placements,
        group.contentZone: updatedZonePlacements,
      },
      slotTypes: {
        for (final entry in currentParentConfig.slotTypes.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
        listId: 'registry:ListView',
      },
      slotLabels: {
        for (final entry in currentParentConfig.slotLabels.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
        listId: userConfig.arrayKey.trim().isEmpty
            ? group.defaultArrayKey
            : userConfig.arrayKey.trim(),
      },
      slotPreferredSizes: {
        for (final entry in currentParentConfig.slotPreferredSizes.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
      },
      slotSizeConstraints: {
        for (final entry in currentParentConfig.slotSizeConstraints.entries)
          if (!removedFromParent.contains(entry.key)) entry.key: entry.value,
        if (listConstraints != null) listId: listConstraints,
      },
      grid: currentParentConfig.grid?.copyWith(
        items: {
          for (final entry in currentParentConfig.grid!.items.entries)
            if (entry.key == firstNode.slotId)
              listId: entry.value
            else if (!removedFromParent.contains(entry.key))
              entry.key: entry.value,
        },
      ),
    );

    layoutState.updateConfig(nextParentConfig, validateTags: false);
    if (layoutState.effectiveLayoutId case final parentLayoutId?
        when registry.superLayoutConfigById.containsKey(parentLayoutId)) {
      registry.layoutController(parentLayoutId).value = nextParentConfig;
    }

    // 5. Purge orphaned duplicate instances (and unwrapped shell if any)
    for (final dup in group.occurrences.skip(1)) {
      registry.purgeInstance(
        dup.slotId,
        dup.rawSlotType,
        EditorConfigKind.layout,
      );
    }
    if (unwrappedOuterId != null) {
      registry.purgeInstance(
        unwrappedOuterId,
        firstNode.rawSlotType,
        EditorConfigKind.layout,
      );
    }

    return true;
  }

  Future<void> _createRepository() async {
    if (_busy) return;
    final name = _repoName.text.trim();
    if (name.isEmpty) {
      setState(() {
        _status = null;
        _error = 'Indiquez un nom de repository.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final decoded = jsonDecode(_json.text);
      final store =
          widget.store ?? (_ownedStore ??= JsonRepositoryStore.defaultStore());
      final existingNames = await store.list();
      final existingMatch = existingNames
          .where((entry) => entry.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (existingMatch != null) {
        final previousText = await store.read(existingMatch);
        Object? merged = decoded;
        try {
          final previousDecoded = jsonDecode(previousText);
          if (previousDecoded is Map && decoded is Map) {
            merged = <String, Object?>{
              for (final entry in previousDecoded.entries)
                entry.key.toString(): entry.value,
              for (final entry in decoded.entries)
                entry.key.toString(): entry.value,
            };
          }
        } on FormatException {
          merged = decoded;
        }
        final formatted =
            '${const JsonEncoder.withIndent('  ').convert(merged)}\n';
        await store.save(existingMatch, formatted, expectedText: previousText);
      } else {
        final formatted =
            '${const JsonEncoder.withIndent('  ').convert(decoded)}\n';
        await store.create(name);
        await store.save(name, formatted, expectedText: '{}\n');
      }
      final targetName = existingMatch ?? name;
      final repoId = await store.idOf(targetName);
      var convertedListsCount = 0;

      if (_autoBind &&
          (widget.targets.isNotEmpty || _detectedGroups.isNotEmpty)) {
        final payload = _buildExtractedPayload();
        final ownerCtx =
            (widget.ownerContext != null && widget.ownerContext!.mounted)
            ? widget.ownerContext!
            : context;
        final history =
            EditorHistoryScope.controllerOf(ownerCtx) ??
            (mounted ? EditorHistoryScope.controllerOf(context) : null);
        history?.beginTransaction();
        try {
          // 1. Bind standalone targets
          for (final target in widget.targets) {
            final propPaths = payload.paths[(target.kind, target.id)];
            if (propPaths == null || propPaths.isEmpty) continue;
            target.applyBindings({
              for (final entry in propPaths.entries)
                entry.key: JsonTextBinding(
                  repositoryId: repoId,
                  path: entry.value,
                ),
            });
          }

          // 2. Bind or convert recurring block groups
          for (final group in _detectedGroups) {
            final cfg = _groupConfigs[group.id];
            if (cfg == null || !cfg.enabled) continue;
            final arrayPath = payload.groupArrayPaths[group.id];
            if (arrayPath == null || arrayPath.isEmpty) continue;

            if (cfg.convertToListView) {
              final converted = _convertGroupToListView(
                ownerContext: ownerCtx,
                group: group,
                userConfig: cfg,
                repoId: repoId,
                arrayPath: arrayPath,
                groupFieldRelativePaths: payload.groupFieldRelativePaths,
              );
              if (converted) convertedListsCount++;
            } else {
              // Bind each occurrence in-place to arrayPath[i].field
              for (
                var occIdx = 0;
                occIdx < group.occurrences.length;
                occIdx++
              ) {
                for (final field in group.fields) {
                  final relPaths = payload
                      .groupFieldRelativePaths[(group.id, field.fieldKey)];
                  if (relPaths == null || relPaths.isEmpty) continue;
                  final target = field.occurrenceTargets[occIdx];
                  if (target == null) continue;
                  target.applyBindings({
                    for (final entry in relPaths.entries)
                      entry.key: JsonTextBinding(
                        repositoryId: repoId,
                        path: '$arrayPath[$occIdx].${entry.value}',
                      ),
                  });
                }
              }
            }
          }
        } finally {
          history?.commitTransaction();
        }
      }
      if (!mounted) return;
      setState(() {
        if (!_autoBind || (widget.targets.isEmpty && _detectedGroups.isEmpty)) {
          _status = 'Repository « $targetName » créé.';
        } else if (convertedListsCount > 0) {
          _status =
              'Repository « $targetName » enregistré, liaisons appliquées et '
              '$convertedListsCount ListView créée${convertedListsCount > 1 ? 's' : ''}.';
        } else {
          _status =
              'Repository « $targetName » enregistré et liaisons appliquées.';
        }
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _error = 'Erreur de fichier : ${error.message}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildRecurrenceSettingsPanel(ColorScheme scheme) {
    final opts = _recurrenceOptions;
    return DecoratedBox(
      key: const ValueKey('super-value-extract-recurrence-panel'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tolérance de similarité & Arborescence JSON',
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'Min. ${opts.minOccurrences} blocs',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SegmentedButton<RecurrenceSimilarityMode>(
              key: const ValueKey('super-value-extract-similarity-mode'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                for (final mode in RecurrenceSimilarityMode.values)
                  ButtonSegment(
                    value: mode,
                    tooltip: mode.description,
                    label: Text(
                      mode.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
              selected: {opts.similarityMode},
              onSelectionChanged: _busy
                  ? null
                  : (selected) => _updateRecurrenceOptions(
                      opts.copyWith(similarityMode: selected.single),
                    ),
            ),
            if (opts.similarityMode == RecurrenceSimilarityMode.flexible) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Seuil de similarité : ${(opts.similarityThreshold * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey(
                        'super-value-extract-similarity-threshold',
                      ),
                      min: 0.50,
                      max: 1.0,
                      divisions: 10,
                      value: opts.similarityThreshold.clamp(0.50, 1.0),
                      onChanged: _busy
                          ? null
                          : (val) => _updateRecurrenceOptions(
                              opts.copyWith(similarityThreshold: val),
                            ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<JsonExtractHierarchyMode>(
                    key: const ValueKey('super-value-extract-hierarchy-mode'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: [
                      for (final mode in JsonExtractHierarchyMode.values)
                        ButtonSegment(
                          value: mode,
                          tooltip: mode.description,
                          label: Text(
                            mode.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                    selected: {opts.hierarchyMode},
                    onSelectionChanged: _busy
                        ? null
                        : (selected) => _updateRecurrenceOptions(
                            opts.copyWith(hierarchyMode: selected.single),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<int>(
                  key: const ValueKey('super-value-extract-min-occurrences'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 2,
                      tooltip: 'Au moins 2 blocs similaires',
                      label: Text('≥2', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 3,
                      tooltip: 'Au moins 3 blocs similaires',
                      label: Text('≥3', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 4,
                      tooltip: 'Au moins 4 blocs similaires',
                      label: Text('≥4', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {opts.minOccurrences.clamp(2, 4)},
                  onSelectionChanged: _busy
                      ? null
                      : (selected) => _updateRecurrenceOptions(
                          opts.copyWith(minOccurrences: selected.single),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  key: const ValueKey('super-value-extract-opt-contiguous'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.contiguousOnly,
                  label: const Text('Blocs contigus uniquement'),
                  onSelected: _busy
                      ? null
                      : (v) => _updateRecurrenceOptions(
                          opts.copyWith(contiguousOnly: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey('super-value-extract-opt-leaf-slots'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.includeSingleLeafSlots,
                  label: const Text('Inclure composants simples'),
                  onSelected: _busy
                      ? null
                      : (v) => _updateRecurrenceOptions(
                          opts.copyWith(includeSingleLeafSlots: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey(
                    'super-value-extract-opt-ignore-container',
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.ignoreContainerType,
                  label: const Text('Ignorer type de conteneur'),
                  onSelected: _busy
                      ? null
                      : (v) => _updateRecurrenceOptions(
                          opts.copyWith(ignoreContainerType: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey('super-value-extract-opt-same-zones'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.requireSameZoneStructure,
                  label: const Text('Mêmes zones internes'),
                  onSelected: _busy
                      ? null
                      : (v) => _updateRecurrenceOptions(
                          opts.copyWith(requireSameZoneStructure: v),
                        ),
                ),
                FilterChip(
                  key: const ValueKey(
                    'super-value-extract-opt-divergent-props',
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: opts.autoSelectDivergentProperties,
                  label: const Text('Auto-sélectionner propriétés variables'),
                  onSelected: _busy
                      ? null
                      : (v) => _updateRecurrenceOptions(
                          opts.copyWith(autoSelectDivergentProperties: v),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecurringGroupCard(
    DetectedRecurringBlockGroup group,
    ColorScheme scheme,
  ) {
    final cfg = _groupConfigs[group.id]!;
    final keyController = _groupKeyControllers[group.id]!;
    final simPercent = (group.similarityScore * 100).round();

    return Padding(
      key: ValueKey('super-value-extract-group-${group.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cfg.enabled
              ? scheme.primaryContainer.withValues(alpha: 0.22)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cfg.enabled
                ? scheme.primary.withValues(alpha: 0.65)
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 16,
                    color: cfg.enabled
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Bloc récurrent : ${group.occurrences.length} × ${group.blockDisplayName}',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Similarité $simPercent%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    key: ValueKey(
                      'super-value-extract-group-enable-${group.id}',
                    ),
                    value: cfg.enabled,
                    onChanged: _busy
                        ? null
                        : (v) => _updateGroupConfig(
                            group.id,
                            cfg.copyWith(enabled: v),
                          ),
                  ),
                ],
              ),
              if (cfg.enabled) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        key: ValueKey(
                          'super-value-extract-group-key-${group.id}',
                        ),
                        controller: keyController,
                        enabled: !_busy,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Clé du tableau JSON',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => _updateGroupConfig(
                          group.id,
                          cfg.copyWith(arrayKey: val),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: ValueKey(
                        'super-value-extract-group-listview-${group.id}',
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.view_list, size: 15),
                      selected: cfg.convertToListView,
                      label: const Text('Remplacer par ListView'),
                      onSelected: _busy
                          ? null
                          : (v) => _updateGroupConfig(
                              group.id,
                              cfg.copyWith(convertToListView: v),
                            ),
                    ),
                  ],
                ),
                if (cfg.convertToListView) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        key: ValueKey(
                          'super-value-extract-group-axis-${group.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          cfg.wrap
                              ? Icons.wrap_text
                              : cfg.axis == Axis.vertical
                              ? Icons.swap_vert
                              : Icons.swap_horiz,
                          size: 14,
                        ),
                        label: Text(
                          cfg.wrap
                              ? 'Disposition : Wrap'
                              : cfg.axis == Axis.vertical
                              ? 'Disposition : Verticale'
                              : 'Disposition : Horizontale',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: _busy
                            ? null
                            : () {
                                if (!cfg.wrap && cfg.axis == Axis.vertical) {
                                  _updateGroupConfig(
                                    group.id,
                                    cfg.copyWith(
                                      axis: Axis.horizontal,
                                      wrap: false,
                                    ),
                                  );
                                } else if (!cfg.wrap &&
                                    cfg.axis == Axis.horizontal) {
                                  _updateGroupConfig(
                                    group.id,
                                    cfg.copyWith(
                                      axis: Axis.vertical,
                                      wrap: true,
                                    ),
                                  );
                                } else {
                                  _updateGroupConfig(
                                    group.id,
                                    cfg.copyWith(
                                      axis: Axis.vertical,
                                      wrap: false,
                                    ),
                                  );
                                }
                              },
                      ),
                      if (group.canUnwrapContainer)
                        ActionChip(
                          key: ValueKey(
                            'super-value-extract-group-template-mode-${group.id}',
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          avatar: const Icon(Icons.layers_outlined, size: 14),
                          tooltip: cfg.templateMode.description,
                          label: Text(
                            cfg.templateMode.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: _busy
                              ? null
                              : () => _updateGroupConfig(
                                  group.id,
                                  cfg.copyWith(
                                    templateMode:
                                        cfg.templateMode ==
                                            ListViewTemplateMode.preserveBlock
                                        ? ListViewTemplateMode.unwrapContainer
                                        : ListViewTemplateMode.preserveBlock,
                                  ),
                                ),
                        ),
                      FilterChip(
                        key: ValueKey(
                          'super-value-extract-group-allow-add-${group.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: cfg.allowAdd,
                        label: const Text(
                          'Bouton Ajouter',
                          style: TextStyle(fontSize: 11),
                        ),
                        onSelected: _busy
                            ? null
                            : (v) => _updateGroupConfig(
                                group.id,
                                cfg.copyWith(allowAdd: v),
                              ),
                      ),
                      FilterChip(
                        key: ValueKey(
                          'super-value-extract-group-allow-remove-${group.id}',
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: cfg.allowRemove,
                        label: const Text(
                          'Bouton Supprimer',
                          style: TextStyle(fontSize: 11),
                        ),
                        onSelected: _busy
                            ? null
                            : (v) => _updateGroupConfig(
                                group.id,
                                cfg.copyWith(allowRemove: v),
                              ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                for (final field in group.fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${field.displayName} (${field.kind.label})',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${cfg.arrayKey}[?].${field.fieldKey}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final prop in field.properties)
                              () {
                                final firstVal =
                                    field.occurrenceValues.first[prop.id];
                                final lastVal =
                                    field.occurrenceValues.last[prop.id];
                                final varies = field.divergentPropertyIds
                                    .contains(prop.id);
                                final previewText = varies
                                    ? '${prop.label} : $firstVal … $lastVal'
                                    : '${prop.label} : $firstVal';
                                final isSelected =
                                    (_selectedGroupFieldProps[(
                                              group.id,
                                              field.fieldKey,
                                            )] ??
                                            const {})
                                        .contains(prop.id);
                                return FilterChip(
                                  key: ValueKey(
                                    'super-value-extract-group-prop-${group.id}-${field.fieldKey}-${prop.id}',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  selected: isSelected,
                                  label: Text(previewText),
                                  onSelected: _busy
                                      ? null
                                      : (sel) => _toggleGroupFieldProperty(
                                          group,
                                          field,
                                          prop.id,
                                          sel,
                                        ),
                                );
                              }(),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.sourceLabel == null || widget.sourceLabel!.isEmpty
        ? 'Extraire en JSON'
        : 'Extraire en JSON : ${widget.sourceLabel}';
    final scheme = Theme.of(context).colorScheme;
    final activeGroups = [
      for (final group in _detectedGroups)
        if (_groupConfigs[group.id]?.enabled ?? true) group,
    ];
    final coveredByActiveGroups = <(ExtractableComponentKind, String)>{
      for (final group in activeGroups) ...group.coveredTargetKeys,
    };
    final standaloneTargets = [
      for (final target in widget.targets)
        if (!coveredByActiveGroups.contains((target.kind, target.id))) target,
    ];
    final hasAnyTargets =
        widget.targets.isNotEmpty || _detectedGroups.isNotEmpty;

    return AlertDialog(
      key: const ValueKey('super-value-extract-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      title: EditorDialogHeader(label: title),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasAnyTargets || _effectiveRootSlot != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _detectedGroups.isEmpty
                            ? 'Propriétés à extraire'
                            : 'Propriétés & Blocs récurrents (${_detectedGroups.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey(
                        'super-value-extract-recurrence-settings-toggle',
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      onPressed: () => setState(
                        () =>
                            _showRecurrenceSettings = !_showRecurrenceSettings,
                      ),
                      icon: Icon(
                        _showRecurrenceSettings
                            ? Icons.expand_less
                            : Icons.tune_outlined,
                        size: 16,
                      ),
                      label: Text(
                        _showRecurrenceSettings
                            ? 'Masquer paramètres'
                            : 'Similarité & Options',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (_showRecurrenceSettings) ...[
                  const SizedBox(height: 6),
                  _buildRecurrenceSettingsPanel(scheme),
                ],
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: _showRecurrenceSettings ? 180 : 260,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey('super-value-extract-targets'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final group in _detectedGroups)
                          _buildRecurringGroupCard(group, scheme),
                        for (final target in standaloneTargets)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${target.displayName} (${target.kind.label})',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          'clé : ${target.baseJsonKey}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                                fontFamily: 'monospace',
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final prop in target.properties)
                                          FilterChip(
                                            key: ValueKey(
                                              'super-value-extract-prop-${target.id}-${prop.id}',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            selected:
                                                (_selectedProps[(
                                                          target.kind,
                                                          target.id,
                                                        )] ??
                                                        const {})
                                                    .contains(prop.id),
                                            label: Text(
                                              '${prop.label} : ${prop.value}',
                                            ),
                                            onSelected: _busy
                                                ? null
                                                : (selected) => _toggleProperty(
                                                    target,
                                                    prop.id,
                                                    selected,
                                                  ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                height: 140,
                child: TextField(
                  key: const ValueKey('super-value-extract-json'),
                  controller: _json,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'JSON extrait',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              if (hasAnyTargets) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  key: const ValueKey('super-value-extract-auto-bind'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _autoBind,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _autoBind = value ?? true),
                  title: const Text(
                    'Lier automatiquement les propriétés sélectionnées au repository',
                  ),
                ),
              ],
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('super-value-extract-repo-name'),
                controller: _repoName,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Nom du repository',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _busy ? null : (_) => _createRepository(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  key: const ValueKey('super-value-extract-error'),
                  style: TextStyle(color: scheme.error),
                ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 6),
                Text(
                  _status!,
                  key: const ValueKey('super-value-extract-status'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('super-value-extract-copy'),
          onPressed: _copy,
          icon: const Icon(Icons.copy),
          label: const Text('Copier'),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('super-value-extract-create-repo'),
          onPressed: _busy ? null : _createRepository,
          icon: const Icon(Icons.storage_outlined),
          label: Text(
            _autoBind && hasAnyTargets
                ? 'Valider et lier'
                : 'Créer un repository',
          ),
        ),
        FilledButton(
          key: const ValueKey('super-value-extract-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
