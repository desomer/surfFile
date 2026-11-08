/// Modèles et fonctions utilitaires partagés entre les composants de collection JSON
/// (`SuperListView`, `SuperTable`, `SuperTab`, `SuperTreeView`).
///
/// Mutualise la résolution de source de tableau ([ResolvedJsonArraySource]),
/// l'adaptation vers [NativeComponentConfig], le rendu des zones répétées,
/// la boîte de dialogue de suppression d'élément et l'habillage [RawScrollbar].
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/super_layout_config.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_binding.dart';
import '../../services/repositories/json_repository_store.dart';
import '../editing/components/native_component_editor.dart';
import '../editing/history/editor_history.dart';
import 'super_layout/slot_implementation.dart';

/// Tableau ou nœud JSON résolu pour un composant de collection.
@immutable
class ResolvedJsonArraySource {
  const ResolvedJsonArraySource({
    this.binding,
    this.error,
    this.unselected = false,
    this.parents = const [],
    this.rowBase = const [],
    this.arrays = const [],
  });

  /// Liaison concrète résolue (sans joker `[?]` non résolu).
  final JsonTextBinding? binding;

  /// Message d'erreur éventuel lors de la résolution du chemin.
  final String? error;

  /// Vrai lorsqu'un `[?]` parent du chemin n'a aucune ligne sélectionnée.
  final bool unselected;

  /// Valeurs des indices `[?]` parents du chemin du tableau.
  final List<int> parents;

  /// Indices transmis aux lignes enfants avant leur propre indice.
  final List<int> rowBase;

  /// Sélections de tableaux dont dépend la résolution du chemin.
  final List<JsonArrayBinding> arrays;

  @override
  bool operator ==(Object other) =>
      other is ResolvedJsonArraySource &&
      other.binding == binding &&
      other.error == error &&
      other.unselected == unselected &&
      listEquals(other.parents, parents) &&
      listEquals(other.rowBase, rowBase) &&
      listEquals(other.arrays, arrays);

  @override
  int get hashCode => Object.hash(
    binding,
    error,
    unselected,
    Object.hashAll(parents),
    Object.hashAll(rowBase),
    Object.hashAll(arrays),
  );
}

/// Résout [binding] dans le contexte de [scope] et [store] vers un [ResolvedJsonArraySource].
ResolvedJsonArraySource resolveJsonArraySource(
  JsonTextBinding? binding,
  JsonListScope? scope,
  JsonRepositoryStore? store,
) {
  if (binding == null) return const ResolvedJsonArraySource();
  try {
    final resolved = JsonListScope.resolveSelected(binding, scope, store);
    final scoped = scope?.indices ?? const <int>[];
    return ResolvedJsonArraySource(
      binding: resolved.binding,
      unselected: resolved.binding == null,
      parents: resolved.indices,
      rowBase: resolved.indices.length > scoped.length
          ? resolved.indices
          : scoped,
      arrays: resolved.arrays,
    );
  } on FormatException catch (error) {
    return ResolvedJsonArraySource(error: error.message);
  }
}

/// Met à jour la liste des [JsonArrayBinding] écoutés avec [listener].
List<JsonArrayBinding> updateWatchedArrayBindings(
  List<JsonArrayBinding> previous,
  List<JsonArrayBinding> next,
  VoidCallback listener,
) {
  for (final array in previous) {
    array.removeListener(listener);
  }
  for (final array in next) {
    array.addListener(listener);
  }
  return next;
}

/// Affiche la boîte de dialogue de confirmation de suppression d'un élément de collection.
Future<bool> confirmRemoveCollectionItemDialog(
  BuildContext context,
  int index,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Supprimer l’élément ?'),
      content: Text('L’élément ${index + 1} sera retiré du repository.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Enveloppe [child] dans une [RawScrollbar] configurée par [scrollbarStyle] lorsque [showScrollbar] est actif.
Widget wrapWithConfiguredScrollbar({
  required BuildContext context,
  required Key scrollbarKey,
  required ScrollController controller,
  required Axis scrollAxis,
  required bool showScrollbar,
  required ScrollbarStyleConfig scrollbarStyle,
  required Widget child,
}) {
  Widget scrollView = ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: child,
  );
  if (showScrollbar) {
    final colors = Theme.of(context).colorScheme;
    scrollView = RawScrollbar(
      key: scrollbarKey,
      controller: controller,
      thumbVisibility: scrollbarStyle.thumbVisibility,
      trackVisibility: scrollbarStyle.trackVisibility,
      interactive: scrollbarStyle.interactive,
      thickness: scrollbarStyle.thickness,
      radius: Radius.circular(scrollbarStyle.radius),
      mainAxisMargin: scrollbarStyle.mainAxisMargin,
      crossAxisMargin: scrollbarStyle.crossAxisMargin,
      thumbColor:
          scrollbarStyle.thumbColor ??
          colors.onSurfaceVariant.withValues(alpha: 0.45),
      trackColor:
          scrollbarStyle.trackColor ??
          colors.surfaceContainerHighest.withValues(alpha: 0.35),
      trackBorderColor:
          scrollbarStyle.trackBorderColor ??
          (scrollbarStyle.trackVisibility
              ? colors.outlineVariant.withValues(alpha: 0.5)
              : const Color(0x00000000)),
      scrollbarOrientation: scrollbarStyle.side.resolveOrientation(scrollAxis),
      child: scrollView,
    );
  }
  return scrollView;
}

/// Construit un [NativeComponentConfig] filtré sur [activeRegionIds] pour le pont
/// d'édition avec [NativeComponentEditor] (`SuperTab`, `SuperTable`, `SuperTreeView`).
NativeComponentConfig buildNativeComponentConfigFromRegions({
  required Set<String> activeRegionIds,
  required Map<String, List<String>> placements,
  required Map<String, String> slotTypes,
  required Map<String, Axis> zoneAxes,
  required Map<String, ZoneFlowConfig> zoneFlows,
  required Map<String, Size?> slotPreferredSizes,
  required Map<String, SlotSizeConstraints> slotSizeConstraints,
  required Map<String, String> slotLabels,
}) {
  final activePlacements = <String, List<String>>{
    for (final entry in placements.entries)
      if (activeRegionIds.contains(entry.key)) entry.key: entry.value,
  };
  final activeSlotIds = activePlacements.values.expand((ids) => ids).toSet();
  return NativeComponentConfig(
    regions: {for (final id in activeRegionIds) id: true},
    placements: activePlacements,
    slotTypes: {
      for (final entry in slotTypes.entries)
        if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
    },
    regionAxes: {
      for (final entry in zoneAxes.entries)
        if (activeRegionIds.contains(entry.key)) entry.key: entry.value,
    },
    regionFlows: {
      for (final entry in zoneFlows.entries)
        if (activeRegionIds.contains(entry.key)) entry.key: entry.value,
    },
    slotPreferredSizes: {
      for (final entry in slotPreferredSizes.entries)
        if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
    },
    slotSizeConstraints: {
      for (final entry in slotSizeConstraints.entries)
        if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
    },
    slotLabels: {
      for (final entry in slotLabels.entries)
        if (activeSlotIds.contains(entry.key)) entry.key: entry.value,
    },
  );
}

/// Construit le contenu d'une zone répétée dans `SuperTable` ou `SuperTreeView`
/// (région interactive pour la 1re ligne/en-tête, ou [SlotStack] pour les lignes suivantes).
Widget buildRepeatedRegionZoneContent({
  required BuildContext context,
  required NativeComponentEditorState editor,
  required String zoneId,
  required bool isInteractiveRegion,
  required Map<String, Size?> slotPreferredSizes,
  required Map<String, SlotSizeConstraints> slotSizeConstraints,
}) {
  final Widget content;
  if (isInteractiveRegion) {
    content = editor.region(zoneId, expand: true, stretch: true);
  } else {
    final slots = editor.slotsFor(zoneId);
    if (slots.isEmpty) {
      return const SizedBox.shrink();
    }
    final axis = editor.axisOf(zoneId);
    final flow = editor.flowOf(zoneId);
    content = SlotStack(
      slots: slots,
      axis: axis,
      flow: flow,
      expand: true,
      stretch: true,
      preferredSizes: {
        for (final slot in slots)
          if (slot case NativePreferredSizeWidget native)
            slot.id: native.preferredSizeIn(context),
        ...slotPreferredSizes,
      },
      sizeConstraints: slotSizeConstraints,
    );
  }
  return SlotContentFitScope(fitWidth: false, fitHeight: false, child: content);
}

/// Supprime un slot d'un composant multi-zones (`SuperTab`, `SuperTable`, `SuperTreeView`)
/// dans une transaction [EditorHistoryScope] et purge ses configurations dans [registry].
Future<void> purgeRemovedComponentSlots<C>({
  required BuildContext context,
  required ValueNotifier<C> controller,
  required Registry? registry,
  required EditorConfigKind ownerKind,
  required Set<String> removedIds,
  required String Function(String id) slotTypeOf,
  required C nextConfig,
}) async {
  final removedTypes = {for (final id in removedIds) id: slotTypeOf(id)};
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  try {
    controller.value = nextConfig;
    if (registry != null) {
      for (final entry in removedTypes.entries) {
        registry.purgeInstance(entry.key, entry.value, ownerKind);
      }
    }
  } finally {
    history?.commitTransaction();
  }
}
