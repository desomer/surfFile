/// Construit le document JSON extrait et les chemins de ses liaisons.
library;

import 'extract_contracts.dart';

/// Résultat JSON et chemins des propriétés à lier aux repositories.
typedef ExtractedPayload = ({
  Map<String, Object?> json,
  Map<(ExtractableComponentKind, String), Map<String, String>> paths,
  Map<String, String> groupArrayPaths,
  Map<(String, String), Map<String, String>> groupFieldRelativePaths,
});

/// Assemblage sans état du payload JSON et de ses chemins de liaison.
abstract final class ExtractPayloadBuilder {
  /// Construit un payload à partir des cibles et sélections courantes.
  static ExtractedPayload build({
    required List<ExtractableComponentTarget> targets,
    required Map<(ExtractableComponentKind, String), Set<String>> selectedProps,
    required List<DetectedRecurringBlockGroup> detectedGroups,
    required Map<String, RecurringGroupUserConfig> groupConfigs,
    required Map<(String, String), Set<String>> selectedGroupFieldProps,
    required JsonExtractRecurrenceOptions recurrenceOptions,
  }) {
    final json = <String, Object?>{};
    final paths = <(ExtractableComponentKind, String), Map<String, String>>{};
    final groupArrayPaths = <String, String>{};
    final groupFieldRelativePaths = <(String, String), Map<String, String>>{};

    final activeGroups = [
      for (final group in detectedGroups)
        if (groupConfigs[group.id]?.enabled ?? true) group,
    ];
    final coveredByActiveGroups = <(ExtractableComponentKind, String)>{
      for (final group in activeGroups) ...group.coveredTargetKeys,
    };

    for (final target in targets) {
      final targetKey = (target.kind, target.id);
      if (coveredByActiveGroups.contains(targetKey)) continue;
      final selectedIds = selectedProps[targetKey] ?? const {};
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

    final usedArrayPaths = <String>{...json.keys};
    for (final group in activeGroups) {
      final config = groupConfigs[group.id]!;
      final rawArrayKey = sanitizeJsonAttributeKey(
        config.arrayKey.trim().isEmpty
            ? group.defaultArrayKey
            : config.arrayKey,
      );
      var arrayKey = rawArrayKey;
      var suffix = 2;
      while (!usedArrayPaths.add(arrayKey)) {
        arrayKey = '${rawArrayKey}_$suffix';
        suffix++;
      }

      final fullArrayPath = _joinJsonPath(
        recurrenceOptions.hierarchyMode,
        group.containerPath,
        arrayKey,
      );
      groupArrayPaths[group.id] = fullArrayPath;

      final items = <Map<String, Object?>>[];
      for (
        var occurrenceIndex = 0;
        occurrenceIndex < group.occurrences.length;
        occurrenceIndex++
      ) {
        final itemMap = <String, Object?>{};
        for (final field in group.fields) {
          final selectedIds =
              selectedGroupFieldProps[(group.id, field.fieldKey)] ?? const {};
          final chosen = [
            for (final prop in field.properties)
              if (selectedIds.contains(prop.id)) prop,
          ];
          if (chosen.isEmpty) continue;
          final occurrenceValues = field.occurrenceValues[occurrenceIndex];
          if (chosen.length == 1) {
            final single = chosen.single;
            itemMap[field.fieldKey] = occurrenceValues[single.id];
            if (occurrenceIndex == 0) {
              groupFieldRelativePaths[(group.id, field.fieldKey)] = {
                single.id: field.fieldKey,
              };
            }
          } else {
            itemMap[field.fieldKey] = {
              for (final prop in chosen) prop.id: occurrenceValues[prop.id],
            };
            if (occurrenceIndex == 0) {
              groupFieldRelativePaths[(group.id, field.fieldKey)] = {
                for (final prop in chosen)
                  prop.id: '${field.fieldKey}.${prop.id}',
              };
            }
          }
        }
        items.add(itemMap);
      }

      _placeAtContainerPath(
        json,
        recurrenceOptions.hierarchyMode,
        group.containerPath,
        arrayKey,
        items,
      );
    }

    return (
      json: json,
      paths: paths,
      groupArrayPaths: groupArrayPaths,
      groupFieldRelativePaths: groupFieldRelativePaths,
    );
  }

  static void _placeAtContainerPath(
    Map<String, Object?> root,
    JsonExtractHierarchyMode hierarchyMode,
    List<String> containerPath,
    String key,
    Object? value,
  ) {
    if (hierarchyMode != JsonExtractHierarchyMode.nestedContainers ||
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

  static String _joinJsonPath(
    JsonExtractHierarchyMode hierarchyMode,
    List<String> prefix,
    String leaf,
  ) {
    if (hierarchyMode != JsonExtractHierarchyMode.nestedContainers ||
        prefix.isEmpty) {
      return leaf;
    }
    return '${prefix.join('.')}.$leaf';
  }
}
