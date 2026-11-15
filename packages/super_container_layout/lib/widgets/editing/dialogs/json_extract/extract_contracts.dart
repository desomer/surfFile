/// Contrats et options de détection des composants extractibles vers JSON.
library;

import 'package:material_ui/material_ui.dart';

import '../../../../models/json_text_binding.dart';
import '../../../../models/super_layout_config.dart';
import '../../../components/super_layout/super_layout.dart';
import '../../slots/editable_surface.dart';
import '../../slots/editor_slot.dart';

/// Famille du composant source lors d'une extraction de valeur vers un repository JSON.
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

/// Option décrivant une propriété extractible vers un attribut JSON.
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

/// Cible d'extraction JSON regroupant l'identifiant du composant et ses propriétés extractibles.
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

/// Interface implémentée par les états d'éditeurs capables d'extraire une valeur vers un repository JSON.
abstract interface class JsonExtractableState {
  String get extractableId;
  ExtractableComponentKind get extractableKind;
  EditorSlotState? get extractableSurface;
  BuildContext get extractableContext;
  bool get isExtractableMounted;
  String get preferredExtractableKey;
  ExtractableComponentTarget buildExtractableTarget(String assignedBaseKey);
}

/// Remplace les caractères incompatibles avec une clé d'attribut JSON.
String sanitizeJsonAttributeKey(String raw) {
  final sanitized = raw
      .trim()
      .replaceAll(RegExp(r'[.\[\]\s?]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? 'item' : sanitized;
}

/// Normalise un type de slot en retirant ses préfixes de registre.
String normalizeExtractableSlotType(String rawType) {
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
/// Retire un suffixe numérique utilisé pour distinguer des rôles répétés.
String stripExtractableTrailingIndex(String raw) {
  final trimmed = raw.trim();
  final stripped = trimmed.replaceFirst(RegExp(r'[\s_\-#]*\d+$'), '').trim();
  return stripped.isEmpty ? trimmed : stripped;
}

/// Indique si un type normalisé représente un conteneur de slots.
bool isExtractableContainerSlotType(String normalizedType) => const {
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
