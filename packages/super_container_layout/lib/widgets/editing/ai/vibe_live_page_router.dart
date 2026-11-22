/// Résolution dynamique de la page à afficher en direct pendant l'application
/// incrémentale ou finale des patchs Vibe IA ([VibeLivePageRouter]).
///
/// Relie chaque composant, style ou comportement modifié à la page du catalogue
/// ([EditorPageCatalog]) ou à la route racine codée (`'/'`) qui l'héberge afin
/// de maintenir le routeur [EditorPageRouter] sur la page en cours de construction.
library;

import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../../../models/editor_page_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../services/pages/editor_page_router.dart';
import '../../../theme/appearance.dart';
import 'vibe_scope_helpers.dart';

/// Cible de route candidate pour l'aperçu en direct durant un tour Vibe IA.
@immutable
class VibeRouteTarget {
  /// Cible correspondant à la route racine codée `'/'` (`root` / `mainLayout`).
  const VibeRouteTarget.codedRoot() : isCodedRoot = true, page = null;

  /// Cible correspondant à une page déclarée dans [EditorPageCatalog].
  const VibeRouteTarget.catalogPage(EditorPageConfig this.page)
    : isCodedRoot = false;

  /// Indique si la cible désigne la route racine codée `'/'`.
  final bool isCodedRoot;

  /// Configuration de la page du catalogue lorsque [isCodedRoot] vaut `false`.
  final EditorPageConfig? page;

  /// Clé stable identifiant la cible de navigation durant un tour Vibe.
  String get key => isCodedRoot ? '__coded_root__' : 'page:${page!.id}';

  /// Identifiant de la page du catalogue, ou `null` pour la racine codée `'/'`.
  String? get pageId => page?.id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeRouteTarget &&
          other.isCodedRoot == isCodedRoot &&
          other.page?.id == page?.id;

  @override
  int get hashCode => Object.hash(isCodedRoot, page?.id);

  @override
  String toString() =>
      isCodedRoot ? 'VibeRouteTarget(/)' : 'VibeRouteTarget(${page!.id})';
}

/// Décision de navigation calculée pour un palier ou une entrée de flux Vibe IA.
@immutable
class VibeStepNavigationDecision {
  /// Construit une décision de navigation vers [target].
  const VibeStepNavigationDecision({
    required this.target,
    required this.isVisualChange,
  });

  /// Page ou route racine à afficher.
  final VibeRouteTarget target;

  /// Indique si la décision découle d'un changement visuel (`components` / `styles`).
  final bool isVisualChange;
}

class _PageOwnershipIndex {
  _PageOwnershipIndex._({
    required this.hasCodedRoot,
    required this.targets,
    required this.subtreesByKey,
  });

  factory _PageOwnershipIndex.build(
    Appearance appearance,
    EditorPageRouter routing,
  ) {
    final hasCodedRoot = routing.codedRoutes.any(
      (route) => route.path == '/' && route.parameters.isEmpty,
    );
    final pages = appearance.pageCatalog.pages;
    final catalogPageIds = <String>{for (final page in pages) page.id};

    final targets = <VibeRouteTarget>[];
    final subtreesByKey = <String, Set<String>>{};

    for (final page in pages) {
      final target = VibeRouteTarget.catalogPage(page);
      targets.add(target);
      subtreesByKey[target.key] = _collectSubtreeIds(appearance, [page.id]);
    }

    if (hasCodedRoot) {
      const rootTarget = VibeRouteTarget.codedRoot();
      final anyCatalogContainsMainLayout = subtreesByKey.values.any(
        (ids) => ids.contains('mainLayout'),
      );
      final rootSeeds = <String>[
        if (!catalogPageIds.contains('root')) 'root',
        if (!catalogPageIds.contains('mainLayout') &&
            (!anyCatalogContainsMainLayout ||
                _rootIncludesMainLayout(appearance)))
          'mainLayout',
      ];
      targets.add(rootTarget);
      subtreesByKey[rootTarget.key] = _collectSubtreeIds(appearance, rootSeeds);
    }

    return _PageOwnershipIndex._(
      hasCodedRoot: hasCodedRoot,
      targets: targets,
      subtreesByKey: subtreesByKey,
    );
  }

  final bool hasCodedRoot;
  final List<VibeRouteTarget> targets;
  final Map<String, Set<String>> subtreesByKey;

  static bool _rootIncludesMainLayout(Appearance appearance) {
    final rootConfig = appearance.components['root'];
    if (rootConfig == null) return true;
    if (rootConfig is ScaffoldPageConfig) {
      final bodySlots =
          rootConfig.native.placements['body'] ?? const <String>[];
      return bodySlots.isEmpty ||
          bodySlots.contains('scaffold:body') ||
          bodySlots.contains('__provided-child') ||
          bodySlots.contains('mainLayout');
    }
    return false;
  }

  static Set<String> _collectSubtreeIds(
    Appearance appearance,
    Iterable<String> startIds,
  ) {
    final reachable = <String>{};
    final queue = <String>[
      for (final id in startIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!reachable.add(id)) continue;
      final config = appearance.components[id];
      if (config == null) continue;
      for (final childId in VibeScopeHelpers.childrenOfComponent(config)) {
        if (!reachable.contains(childId)) {
          queue.add(childId);
        }
      }
      final itemId = switch (config) {
        SuperListViewConfig(:final itemId) => itemId,
        SuperTreeViewConfig(:final itemId) => itemId,
        SuperTableConfig(:final itemId) => itemId,
        _ => null,
      };
      if (itemId != null && itemId.isNotEmpty && !reachable.contains(itemId)) {
        queue.add(itemId);
      }
    }
    return reachable;
  }

  static List<String> _candidateComponentIds(String rawId) {
    var trimmed = rawId.trim();
    if (trimmed.startsWith('-')) {
      trimmed = trimmed.substring(1).trim();
    }
    if (trimmed.isEmpty || trimmed == 'background') return const <String>[];
    final candidates = <String>[trimmed];
    if (trimmed.contains('::')) {
      final base = trimmed.split('::').first.trim();
      if (base.isNotEmpty && !candidates.contains(base)) {
        candidates.add(base);
      }
    }
    if (trimmed.contains(':') && !trimmed.startsWith('scaffold:')) {
      final base = trimmed.split(':').first.trim();
      if (base.isNotEmpty && !candidates.contains(base)) {
        candidates.add(base);
      }
    }
    return candidates;
  }

  List<VibeRouteTarget> ownersOf(String rawId) {
    final candidates = _candidateComponentIds(rawId);
    if (candidates.isEmpty) return const <VibeRouteTarget>[];
    final matches = <VibeRouteTarget>[];
    for (final target in targets) {
      final subtree = subtreesByKey[target.key]!;
      if (candidates.any(subtree.contains)) {
        matches.add(target);
      }
    }
    return matches;
  }
}

/// Moteur pur de sélection et d'application de la route active durant la construction IA.
abstract final class VibeLivePageRouter {
  static const List<String> _parameterFallbacks = <String>['1', 'demo', 'a'];

  /// Retourne la cible correspondant à l'URI actuellement affichée par [routing], ou `null`.
  static VibeRouteTarget? currentTarget(
    EditorPageRouter routing,
    Appearance appearance,
  ) {
    final currentUri = routing.currentUri;
    final matchedPage = routing.pageAt(
      currentUri,
      catalog: appearance.pageCatalog,
    );
    if (matchedPage != null) {
      return VibeRouteTarget.catalogPage(matchedPage);
    }
    final hasCodedRoot = routing.codedRoutes.any(
      (route) => route.path == '/' && route.parameters.isEmpty,
    );
    if (hasCodedRoot && currentUri.path == '/') {
      return const VibeRouteTarget.codedRoot();
    }
    return null;
  }

  /// Indique si [routing] affiche déjà la page désignée par [target].
  static bool isAlreadyOnTarget(
    EditorPageRouter routing,
    Appearance appearance,
    VibeRouteTarget target,
  ) {
    final currentUri = routing.currentUri;
    if (target.isCodedRoot) {
      final activePage = routing.pageAt(
        currentUri,
        catalog: appearance.pageCatalog,
      );
      return activePage == null && currentUri.path == '/';
    }
    final matched = routing.pageAt(currentUri, catalog: appearance.pageCatalog);
    return matched?.id == target.page!.id;
  }

  /// Construit une URL valide pour [target], en synthétisant au besoin des paramètres d'aperçu.
  static String? resolveLocation(
    EditorPageRouter routing,
    VibeRouteTarget target,
  ) {
    if (target.isCodedRoot) return '/';
    final page = target.page!;
    final List<String> requiredParams;
    try {
      requiredParams = routing.parametersOf(page);
    } on FormatException {
      return null;
    }
    if (requiredParams.isEmpty) {
      try {
        return routing.locationFor(page, const <String, String>{});
      } on FormatException {
        return null;
      }
    }
    if (requiredParams.every(
      (key) => page.defaultParameters[key]?.isNotEmpty == true,
    )) {
      try {
        return routing.locationFor(page, {
          for (final key in requiredParams) key: page.defaultParameters[key]!,
        });
      } on FormatException {
        // Poursuit avec les valeurs de repli si les paramètres par défaut échouent.
      }
    }
    for (final fallback in _parameterFallbacks) {
      final synthesized = <String, String>{
        for (final key in requiredParams)
          key: (page.defaultParameters[key]?.isNotEmpty == true)
              ? page.defaultParameters[key]!
              : fallback,
      };
      try {
        return routing.locationFor(page, synthesized);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// Synchronise [routing] avec [appearance] et navigue vers [target] si nécessaire.
  ///
  /// Retourne `true` lorsqu'un changement effectif de route a été déclenché.
  static bool navigateToTarget({
    required EditorPageRouter routing,
    required Appearance appearance,
    required VibeRouteTarget target,
  }) {
    try {
      routing.synchronize(appearance.pageCatalog);
      if (isAlreadyOnTarget(routing, appearance, target)) {
        return false;
      }
      final location = resolveLocation(routing, target);
      if (location == null || location.isEmpty) return false;
      routing.openLocation(location);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Détermine la cible à afficher lorsqu'une entrée JSON est en cours de réception
  /// avant la fermeture complète de son bloc (`activeSection` / `activeEntryKey`).
  static VibeStepNavigationDecision? resolveForStreamingEntry({
    required EditorPageRouter routing,
    required Appearance appearance,
    required String activeSection,
    required String activeEntryKey,
    required Set<String> initialPageIds,
    required bool hasNavigatedForVisualChange,
  }) {
    final isVisualSection =
        activeSection == 'components' || activeSection == 'styles';
    if (!isVisualSection &&
        (activeSection != 'behaviors' || hasNavigatedForVisualChange)) {
      return null;
    }

    final index = _PageOwnershipIndex.build(appearance, routing);
    final current = currentTarget(routing, appearance);
    final owners = _filterUnpopulatedNewPagesForNonComponent(
      owners: index.ownersOf(activeEntryKey),
      appearance: appearance,
      initialPageIds: initialPageIds,
      isComponentSection: activeSection == 'components',
    );
    if (owners.isEmpty) return null;
    if (current != null && owners.contains(current)) {
      return VibeStepNavigationDecision(
        target: current,
        isVisualChange: isVisualSection,
      );
    }
    if (owners.length == 1) {
      return VibeStepNavigationDecision(
        target: owners.single,
        isVisualChange: isVisualSection,
      );
    }
    return null;
  }

  /// Détermine la cible à afficher après l'application d'un palier incrémental
  /// entre [previousAppearance] et [nextAppearance].
  static VibeStepNavigationDecision? resolveForPreviewStep({
    required EditorPageRouter routing,
    required Appearance previousAppearance,
    required Appearance nextAppearance,
    required Map<String, dynamic> effectivePatch,
    required Set<String> initialPageIds,
    required bool hasNavigatedForVisualChange,
  }) {
    final payload = effectivePatch['data'] is Map<String, dynamic>
        ? effectivePatch['data'] as Map<String, dynamic>
        : effectivePatch;
    final index = _PageOwnershipIndex.build(nextAppearance, routing);
    final current = currentTarget(routing, nextAppearance);

    final stepComponentIds = _orderedChangedKeys(
      patchSection: payload['components'],
      allKeys: <String>{
        ...previousAppearance.components.keys,
        ...nextAppearance.components.keys,
      },
      hasChanged: (id) =>
          previousAppearance.components[id] != nextAppearance.components[id],
    );

    final compTarget = _pickTargetFromOrderedIds(
      orderedIds: stepComponentIds,
      index: index,
      appearance: nextAppearance,
      initialPageIds: initialPageIds,
      isComponentSection: true,
      current: current,
    );
    if (compTarget != null) {
      return VibeStepNavigationDecision(
        target: compTarget,
        isVisualChange: true,
      );
    }

    final stepStyleIds = _orderedChangedKeys(
      patchSection: payload['styles'],
      allKeys: <String>{
        ...previousAppearance.styles.keys,
        ...nextAppearance.styles.keys,
      },
      hasChanged: (id) =>
          id != 'background' &&
          previousAppearance.styles[id] != nextAppearance.styles[id],
    );

    final styleTarget = _pickTargetFromOrderedIds(
      orderedIds: stepStyleIds,
      index: index,
      appearance: nextAppearance,
      initialPageIds: initialPageIds,
      isComponentSection: false,
      current: current,
    );
    if (styleTarget != null) {
      return VibeStepNavigationDecision(
        target: styleTarget,
        isVisualChange: true,
      );
    }

    final previousPageIds = <String>{
      for (final page in previousAppearance.pageCatalog.pages) page.id,
    };
    final stepAddedPages = <EditorPageConfig>[
      for (final page in nextAppearance.pageCatalog.pages)
        if (!previousPageIds.contains(page.id)) page,
    ];
    if (stepAddedPages.isNotEmpty) {
      final homeId = nextAppearance.pageCatalog.homePageId;
      final preferred =
          stepAddedPages.where((page) => page.id == homeId).firstOrNull ??
          stepAddedPages.first;
      return VibeStepNavigationDecision(
        target: VibeRouteTarget.catalogPage(preferred),
        isVisualChange: false,
      );
    }

    if (!hasNavigatedForVisualChange &&
        stepComponentIds.isEmpty &&
        stepStyleIds.isEmpty) {
      final stepBehaviorIds = _orderedChangedKeys(
        patchSection: payload['behaviors'],
        allKeys: <String>{
          ...previousAppearance.behaviors.keys,
          ...nextAppearance.behaviors.keys,
        },
        hasChanged: (id) => !listEquals(
          previousAppearance.behaviors[id],
          nextAppearance.behaviors[id],
        ),
      );
      final behaviorTarget = _pickTargetFromOrderedIds(
        orderedIds: stepBehaviorIds,
        index: index,
        appearance: nextAppearance,
        initialPageIds: initialPageIds,
        isComponentSection: false,
        current: current,
      );
      if (behaviorTarget != null) {
        return VibeStepNavigationDecision(
          target: behaviorTarget,
          isVisualChange: false,
        );
      }
    }

    return null;
  }

  /// Détermine la page finale à afficher à l'issue d'une tentative ou d'un tour/lot complet
  /// entre [baseAppearance] et [finalAppearance].
  static VibeRouteTarget? resolveForTurnOutcome({
    required EditorPageRouter routing,
    required Appearance baseAppearance,
    required Appearance finalAppearance,
    required Set<String> initialPageIds,
  }) {
    final index = _PageOwnershipIndex.build(finalAppearance, routing);
    final current = currentTarget(routing, finalAppearance);

    final exclusiveCompCounts = <VibeRouteTarget, int>{};
    final sharedCompTargets = <VibeRouteTarget>[];
    for (final id in <String>{
      ...baseAppearance.components.keys,
      ...finalAppearance.components.keys,
    }) {
      if (baseAppearance.components[id] == finalAppearance.components[id]) {
        continue;
      }
      final owners = index.ownersOf(id);
      if (owners.length == 1) {
        final target = owners.single;
        exclusiveCompCounts[target] = (exclusiveCompCounts[target] ?? 0) + 1;
      } else if (owners.length > 1) {
        for (final owner in owners) {
          if (!sharedCompTargets.contains(owner)) {
            sharedCompTargets.add(owner);
          }
        }
      }
    }

    final addedPages = <EditorPageConfig>[
      for (final page in finalAppearance.pageCatalog.pages)
        if (!initialPageIds.contains(page.id)) page,
    ];
    if (addedPages.isNotEmpty) {
      final populated = <EditorPageConfig>[
        for (final page in addedPages)
          if (finalAppearance.components.containsKey(page.id)) page,
      ];
      final candidates = populated.isNotEmpty ? populated : addedPages;
      if (current?.pageId != null &&
          candidates.any((page) => page.id == current!.pageId)) {
        return current;
      }
      final homeId = finalAppearance.pageCatalog.homePageId;
      if (homeId != null) {
        final homeCandidate = candidates
            .where((page) => page.id == homeId)
            .firstOrNull;
        if (homeCandidate != null) {
          return VibeRouteTarget.catalogPage(homeCandidate);
        }
      }
      EditorPageConfig best = candidates.first;
      var bestCount =
          exclusiveCompCounts[VibeRouteTarget.catalogPage(best)] ?? 0;
      for (final page in candidates.skip(1)) {
        final count =
            exclusiveCompCounts[VibeRouteTarget.catalogPage(page)] ?? 0;
        if (count > bestCount) {
          best = page;
          bestCount = count;
        }
      }
      return VibeRouteTarget.catalogPage(best);
    }

    if (exclusiveCompCounts.isNotEmpty) {
      return _pickDominantTarget(exclusiveCompCounts, current);
    }

    final exclusiveStyleCounts = <VibeRouteTarget, int>{};
    final sharedStyleTargets = <VibeRouteTarget>[];
    for (final id in <String>{
      ...baseAppearance.styles.keys,
      ...finalAppearance.styles.keys,
    }) {
      if (id == 'background' ||
          baseAppearance.styles[id] == finalAppearance.styles[id]) {
        continue;
      }
      final owners = index.ownersOf(id);
      if (owners.length == 1) {
        final target = owners.single;
        exclusiveStyleCounts[target] = (exclusiveStyleCounts[target] ?? 0) + 1;
      } else if (owners.length > 1) {
        for (final owner in owners) {
          if (!sharedStyleTargets.contains(owner)) {
            sharedStyleTargets.add(owner);
          }
        }
      }
    }
    if (exclusiveStyleCounts.isNotEmpty) {
      return _pickDominantTarget(exclusiveStyleCounts, current);
    }

    final exclusiveBehaviorCounts = <VibeRouteTarget, int>{};
    final sharedBehaviorTargets = <VibeRouteTarget>[];
    for (final id in <String>{
      ...baseAppearance.behaviors.keys,
      ...finalAppearance.behaviors.keys,
    }) {
      if (listEquals(
        baseAppearance.behaviors[id],
        finalAppearance.behaviors[id],
      )) {
        continue;
      }
      final owners = index.ownersOf(id);
      if (owners.length == 1) {
        final target = owners.single;
        exclusiveBehaviorCounts[target] =
            (exclusiveBehaviorCounts[target] ?? 0) + 1;
      } else if (owners.length > 1) {
        for (final owner in owners) {
          if (!sharedBehaviorTargets.contains(owner)) {
            sharedBehaviorTargets.add(owner);
          }
        }
      }
    }
    if (exclusiveBehaviorCounts.isNotEmpty) {
      return _pickDominantTarget(exclusiveBehaviorCounts, current);
    }

    final sharedFallback = <VibeRouteTarget>[
      ...sharedCompTargets,
      ...sharedStyleTargets,
      ...sharedBehaviorTargets,
    ];
    if (sharedFallback.isNotEmpty) {
      if (current != null && sharedFallback.contains(current)) {
        return current;
      }
      return sharedFallback.first;
    }

    return null;
  }

  static VibeRouteTarget _pickDominantTarget(
    Map<VibeRouteTarget, int> counts,
    VibeRouteTarget? current,
  ) {
    var maxCount = 0;
    for (final count in counts.values) {
      if (count > maxCount) maxCount = count;
    }
    final topTargets = <VibeRouteTarget>[
      for (final entry in counts.entries)
        if (entry.value == maxCount) entry.key,
    ];
    if (current != null && topTargets.contains(current)) {
      return current;
    }
    return topTargets.last;
  }

  static List<String> _orderedChangedKeys({
    required Object? patchSection,
    required Set<String> allKeys,
    required bool Function(String id) hasChanged,
  }) {
    final ordered = <String>[];
    final seen = <String>{};
    if (patchSection is Map) {
      for (final rawKey in patchSection.keys) {
        if (rawKey is String && hasChanged(rawKey) && seen.add(rawKey)) {
          ordered.add(rawKey);
        }
      }
    }
    for (final key in allKeys) {
      if (hasChanged(key) && seen.add(key)) {
        ordered.add(key);
      }
    }
    return ordered;
  }

  static List<VibeRouteTarget> _filterUnpopulatedNewPagesForNonComponent({
    required List<VibeRouteTarget> owners,
    required Appearance appearance,
    required Set<String> initialPageIds,
    required bool isComponentSection,
  }) {
    if (isComponentSection || owners.isEmpty) return owners;
    return <VibeRouteTarget>[
      for (final owner in owners)
        if (owner.isCodedRoot ||
            initialPageIds.contains(owner.pageId) ||
            appearance.components.containsKey(owner.pageId))
          owner,
    ];
  }

  static VibeRouteTarget? _pickTargetFromOrderedIds({
    required List<String> orderedIds,
    required _PageOwnershipIndex index,
    required Appearance appearance,
    required Set<String> initialPageIds,
    required bool isComponentSection,
    required VibeRouteTarget? current,
  }) {
    if (orderedIds.isEmpty) return null;
    for (var i = orderedIds.length - 1; i >= 0; i--) {
      final owners = _filterUnpopulatedNewPagesForNonComponent(
        owners: index.ownersOf(orderedIds[i]),
        appearance: appearance,
        initialPageIds: initialPageIds,
        isComponentSection: isComponentSection,
      );
      if (owners.length == 1) {
        return owners.single;
      }
    }
    for (var i = orderedIds.length - 1; i >= 0; i--) {
      final owners = _filterUnpopulatedNewPagesForNonComponent(
        owners: index.ownersOf(orderedIds[i]),
        appearance: appearance,
        initialPageIds: initialPageIds,
        isComponentSection: isComponentSection,
      );
      if (owners.isNotEmpty) {
        if (current != null && owners.contains(current)) {
          return current;
        }
        return owners.first;
      }
    }
    return null;
  }
}
