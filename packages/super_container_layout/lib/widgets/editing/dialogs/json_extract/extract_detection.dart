/// Parcours des composants et détection des blocs récurrents extractibles.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../models/super_layout_config.dart';
import '../../../../models/super_list_view_config.dart';
import '../../../../services/repositories/json_list_scope.dart';
import '../../../../theme/container_style.dart';
import '../../../components/super_layout/super_layout.dart';
import '../../slots/editable_surface.dart';
import '../../slots/editor_slot.dart';
import 'extract_contracts.dart';

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

/// Retourne `true` dès qu'au moins un composant extractible (`SuperValue`,
/// `SuperAction` ou `EditableSurface` avec propriétés extractibles) est trouvé
/// sur [slot] ou dans son sous-arbre, avec arrêt précoce sans construire la liste complète.
bool hasExtractableTargetsInSlot(EditorSlotState slot) {
  if (!slot.mounted) return false;
  var found = false;

  bool hasProperties(JsonExtractableState state) {
    if (!state.isExtractableMounted) return false;
    return state
        .buildExtractableTarget(
          sanitizeJsonAttributeKey(state.preferredExtractableKey),
        )
        .properties
        .isNotEmpty;
  }

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

  if (direct != null) {
    if (hasProperties(direct!)) return true;
    if (direct!.extractableKind != ExtractableComponentKind.surface) {
      return false;
    }
  }

  void visit(Element element) {
    if (found) return;
    if (element is StatefulElement && element.state is JsonExtractableState) {
      final state = element.state as JsonExtractableState;
      if (hasProperties(state)) {
        found = true;
        return;
      }
      if (state.extractableKind != ExtractableComponentKind.surface) {
        return;
      }
    }
    element.visitChildren(visit);
  }

  slot.context.visitChildElements(visit);
  return found;
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
  final normalizedType = normalizeExtractableSlotType(rawType);
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
        : sanitizeJsonAttributeKey(stripExtractableTrailingIndex(rawPref))
              .toLowerCase();
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
      isExtractableContainerSlotType(normalizedType) ||
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
        candidateName = stripExtractableTrailingIndex(entry.target.displayName);
        break;
      }
    }
    if (candidateName == null) {
      final firstEntry = nonNullEntries.first;
      final rawDisplay = firstEntry.target.displayName.trim();
      final isRawId = rawDisplay == firstEntry.target.id;
      if (!isRawId && rawDisplay.isNotEmpty) {
        final stripped = stripExtractableTrailingIndex(rawDisplay);
        // For SuperAction, if each occurrence has a different button text (e.g. 'Voir', 'Acheter'),
        // the button text is the data value, so prefer a semantic key 'action' unless they share a prefix.
        if (kind == ExtractableComponentKind.superAction) {
          final distinctNames = {
            for (final e in nonNullEntries)
              stripExtractableTrailingIndex(e.target.displayName.trim())
                  .toLowerCase(),
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
      candidate = stripExtractableTrailingIndex(occ.customLabel!);
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
