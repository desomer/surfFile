/// Récupération incrémentale et construction de prompts delta pour Vibe IA ([VibeDeltaRecovery]).
///
/// Permet, lorsqu'une tentative de génération échoue en cours ou en fin de flux SSE
/// (composant invalide, contrat de région violé, JSON tronqué ou composant détaché),
/// de sauvegarder tous les composants, styles, comportements, usages et repositories
/// déjà valides afin de ne demander à l'IA qu'un micro-patch correctif (« delta »)
/// au lieu de régénérer toute la page.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import '../../../models/a4_page_config.dart';
import '../../../models/component_behavior.dart';
import '../../../models/component_config.dart';
import '../../../models/component_usage.dart';
import '../../../models/editor_page_config.dart';
import '../../../models/json_syntax.dart';
import '../../../models/native_component_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../theme/appearance.dart';
import '../../../theme/container_style.dart';
import '../slots/editor_context_menu.dart';
import 'vibe_scope_helpers.dart';

/// Résultat immuable de l'analyse de récupération partielle après l'échec d'une tentative Vibe IA.
@immutable
class VibeSalvageOutcome {
  /// Construit un résultat de récupération partielle.
  const VibeSalvageOutcome({
    required this.hasCheckpoint,
    required this.checkpointAppearance,
    required this.rejectedEntries,
    required this.detachedComponentIds,
    required this.missingPlacedComponentIds,
    required this.pendingRequiredComponentIds,
    required this.requiresScreenAttachment,
    required this.wasTruncated,
    this.interruptedSection,
    this.interruptedKey,
  });

  /// Aucun progrès valide exploitable n'a pu être conservé sur cette tentative.
  factory VibeSalvageOutcome.none(
    Appearance fallbackAppearance, {
    List<PatchRejectedEntry> rejectedEntries = const [],
    bool wasTruncated = false,
    String? interruptedSection,
    String? interruptedKey,
  }) => VibeSalvageOutcome(
    hasCheckpoint: false,
    checkpointAppearance: fallbackAppearance,
    rejectedEntries: rejectedEntries,
    detachedComponentIds: const [],
    missingPlacedComponentIds: const [],
    pendingRequiredComponentIds: const {},
    requiresScreenAttachment: false,
    wasTruncated: wasTruncated,
    interruptedSection: interruptedSection,
    interruptedKey: interruptedKey,
  );

  /// Indique si un point de sauvegarde partiel valide a été retenu dans [checkpointAppearance].
  final bool hasCheckpoint;

  /// Apparence partielle validée servant de nouvelle base pour la tentative suivante.
  final Appearance checkpointAppearance;

  /// Entrées individuelles rejetées lors de la validation partielle (`components`, `styles`, `repositories`…).
  final List<PatchRejectedEntry> rejectedEntries;

  /// Identifiants des nouveaux composants valides déjà présents dans [checkpointAppearance]
  /// mais pas encore rattachés à l'arbre de rendu.
  final List<String> detachedComponentIds;

  /// Identifiants de composants nouvellement placés dans `placements` mais absents de `components`.
  final List<String> missingPlacedComponentIds;

  /// Identifiants de composants devant obligatoirement être définis ou corrigés avant validation finale.
  final Set<String> pendingRequiredComponentIds;

  /// Vrai lorsque seuls des composants feuilles non encore rattachés ont été récupérés d'un flux tronqué.
  final bool requiresScreenAttachment;

  /// Indique si la réponse précédente s'est interrompue sur un JSON incomplet/tronqué.
  final bool wasTruncated;

  /// Section JSON active au moment de la troncature éventuelle (`"components"`, `"styles"`, etc.).
  final String? interruptedSection;

  /// Clé d'entrée active au moment de la troncature éventuelle.
  final String? interruptedKey;
}

/// Services statiques de sauvegarde partielle, de nettoyage d'orphelins et de prompt delta.
abstract final class VibeDeltaRecovery {
  static const Set<String> _configurableShortTypes = <String>{
    'Layout',
    'Value',
    'Action',
    'Indicator',
    'IterableContent',
    'ListView',
    'Tab',
    'Conditional',
    'TreeView',
    'Table',
    'Chart',
    'Code',
  };

  /// Calcule l'ensemble des identifiants de composants accessibles depuis l'écran ou le [scope].
  ///
  /// Lorsque [requireNewPageComponent] est vrai, une nouvelle page ajoutée dans `pageCatalog`
  /// (absente de [initialPageIds]) n'est considérée comme racine active que si son composant
  /// racine `page.id` est effectivement défini dans `next.components`.
  static Set<String> computeReachableIds({
    required Appearance baseForScope,
    required Appearance next,
    required VibeChatScope? scope,
    required Set<String>? instantiatedIds,
    required Set<String> initialPageIds,
    bool hasRegistry = true,
    bool requireNewPageComponent = false,
  }) {
    final reachable = <String>{};
    if (scope != null) {
      final pending = <String>[
        ...VibeScopeHelpers.scopeRootIds(baseForScope, scope),
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        pending.addAll(
          VibeScopeHelpers.childrenOfComponent(next.components[id]),
        );
      }
      return reachable;
    }

    final pending = <String>[
      ...?instantiatedIds,
      if (!hasRegistry && instantiatedIds == null)
        ...baseForScope.components.keys,
      for (final shell in next.pageCatalog.shells) shell.id,
      for (final page in next.pageCatalog.pages)
        if (!requireNewPageComponent ||
            initialPageIds.contains(page.id) ||
            next.components.containsKey(page.id))
          page.id,
    ];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!reachable.add(id)) continue;
      final component = next.components[id];
      final children = switch (component) {
        final SuperLayoutConfig layout => layout.placedSlotIds,
        final SuperListViewConfig list => list.template.placedSlotIds,
        final SuperTabConfig tab => tab.placedSlotIds,
        final SuperConditionalConfig cond => cond.placedSlotIds,
        final NativeComponentConfig native => native.placements.values.expand(
          (ids) => ids,
        ),
        final ScaffoldPageConfig scaffold =>
          scaffold.native.placements.values.expand((ids) => ids),
        _ => VibeScopeHelpers.childrenOfComponent(component),
      };
      pending.addAll(children);
    }
    return reachable;
  }

  /// Extrait et valide le maximum d'état sain à partir d'une tentative échouée.
  static VibeSalvageOutcome salvageFailedAttempt({
    required Appearance initialAppearance,
    required Appearance workingAppearance,
    required Set<String> initialPageIds,
    required Set<String>? instantiatedIds,
    required bool hasRegistry,
    required VibeChatScope? scope,
    required AppearanceCodec codec,
    required void Function(Appearance appearance)? validateAppearance,
    required Map<String, dynamic>? effectiveVibePatch,
    required List<PatchRejectedEntry> rejectedRepoEntries,
    required Set<String> appliedRepoKeys,
    required bool wasTruncated,
    String? interruptedSection,
    String? interruptedKey,
  }) {
    if (effectiveVibePatch == null && appliedRepoKeys.isEmpty) {
      return VibeSalvageOutcome.none(
        workingAppearance,
        rejectedEntries: rejectedRepoEntries,
        wasTruncated: wasTruncated,
        interruptedSection: interruptedSection,
        interruptedKey: interruptedKey,
      );
    }

    var candidate = workingAppearance;
    final appliedPatch = <String, dynamic>{};
    final allRejected = <PatchRejectedEntry>[...rejectedRepoEntries];

    if (effectiveVibePatch != null && effectiveVibePatch.isNotEmpty) {
      final partial = AppearanceTransfer.applyVibeMapPartial(
        workingAppearance,
        effectiveVibePatch,
        codec: codec,
      );
      candidate = partial.appearance;
      appliedPatch.addAll(partial.appliedPatch);
      allRejected.addAll(partial.rejectedEntries);
    }

    // Si de nouveaux shells ou de nouvelles pages n'ont pas encore leur composant racine
    // (ex. flux coupé ou entrée orpheline), retire ces entrées incomplètes du checkpoint
    // tout en préservant les shells valides et rootShellId.
    if (candidate.pageCatalog != workingAppearance.pageCatalog) {
      final initialShellIds = {
        for (final shell in initialAppearance.pageCatalog.shells) shell.id,
      };
      final validShells = <EditorShellConfig>[
        for (final shell in candidate.pageCatalog.shells)
          if (initialShellIds.contains(shell.id) ||
              candidate.components.containsKey(shell.id))
            shell,
      ];
      final validShellIds = {for (final s in validShells) s.id};
      final previousPagesById = {
        for (final p in workingAppearance.pageCatalog.pages) p.id: p,
      };
      final validPages = <EditorPageConfig>[];
      for (final page in candidate.pageCatalog.pages) {
        final isInitialPage = initialPageIds.contains(page.id);
        if (!isInitialPage && !candidate.components.containsKey(page.id)) {
          continue;
        }
        if (page.shellId != null && !validShellIds.contains(page.shellId)) {
          if (!isInitialPage) {
            continue;
          }
          final prevShellId = previousPagesById[page.id]?.shellId;
          validPages.add(
            prevShellId != null && validShellIds.contains(prevShellId)
                ? page.copyWith(shellId: prevShellId)
                : page.copyWith(clearShellId: true),
          );
          continue;
        }
        validPages.add(page);
      }

      final validIds = {for (final p in validPages) p.id};
      final prevHome = candidate.pageCatalog.homePageId;
      final nextHome = prevHome != null && validIds.contains(prevHome)
          ? prevHome
          : (workingAppearance.pageCatalog.homePageId != null &&
                    validIds.contains(workingAppearance.pageCatalog.homePageId)
                ? workingAppearance.pageCatalog.homePageId
                : null);
      final prevRootShell = candidate.pageCatalog.rootShellId;
      final nextRootShell =
          prevRootShell != null && validShellIds.contains(prevRootShell)
          ? prevRootShell
          : (workingAppearance.pageCatalog.rootShellId != null &&
                    validShellIds.contains(
                      workingAppearance.pageCatalog.rootShellId,
                    )
                ? workingAppearance.pageCatalog.rootShellId
                : null);

      final catalogChanged =
          validPages.length != candidate.pageCatalog.pages.length ||
          validShells.length != candidate.pageCatalog.shells.length ||
          nextHome != candidate.pageCatalog.homePageId ||
          nextRootShell != candidate.pageCatalog.rootShellId ||
          !_samePageList(validPages, candidate.pageCatalog.pages) ||
          !_sameShellList(validShells, candidate.pageCatalog.shells);
      if (catalogChanged) {
        final restoredCatalog =
            validPages.length == workingAppearance.pageCatalog.pages.length &&
                validShells.length ==
                    workingAppearance.pageCatalog.shells.length &&
                nextHome == workingAppearance.pageCatalog.homePageId &&
                nextRootShell == workingAppearance.pageCatalog.rootShellId &&
                _samePageList(validPages, workingAppearance.pageCatalog.pages) &&
                _sameShellList(
                  validShells,
                  workingAppearance.pageCatalog.shells,
                )
            ? workingAppearance.pageCatalog
            : EditorPageCatalog(
                pages: validPages,
                shells: validShells,
                homePageId: nextHome,
                rootShellId: nextRootShell,
              );
        candidate = candidate.copyWith(pageCatalog: restoredCatalog);
      }
    }

    if (validateAppearance != null && candidate != workingAppearance) {
      try {
        validateAppearance(candidate);
      } catch (error) {
        if (candidate.pageCatalog != workingAppearance.pageCatalog) {
          final rawPageCatalog = effectiveVibePatch == null
              ? null
              : (effectiveVibePatch['data'] is Map
                    ? (effectiveVibePatch['data'] as Map)['pageCatalog']
                    : effectiveVibePatch['pageCatalog']);
          final rawPagesById = <String, Object?>{};
          final rawShellsById = <String, Object?>{};
          if (rawPageCatalog is Map && rawPageCatalog['pages'] is List) {
            for (final rawPage in rawPageCatalog['pages'] as List) {
              if (rawPage is Map && rawPage['id'] is String) {
                rawPagesById[rawPage['id'] as String] = rawPage;
              }
            }
          }
          if (rawPageCatalog is Map && rawPageCatalog['shells'] is List) {
            for (final rawShell in rawPageCatalog['shells'] as List) {
              if (rawShell is Map && rawShell['id'] is String) {
                rawShellsById[rawShell['id'] as String] = rawShell;
              }
            }
          }

          final acceptedShells = <EditorShellConfig>[];
          for (final shell in candidate.pageCatalog.shells) {
            final trialCatalog = EditorPageCatalog(
              shells: [...acceptedShells, shell],
            );
            try {
              validateAppearance(candidate.copyWith(pageCatalog: trialCatalog));
              acceptedShells.add(shell);
            } catch (shellError) {
              allRejected.add(
                PatchRejectedEntry(
                  section: 'pageCatalog',
                  key: shell.id,
                  message: shellError is FormatException
                      ? shellError.message
                      : shellError.toString(),
                  rawValue: rawShellsById[shell.id] ?? shell.toJson(),
                ),
              );
            }
          }
          final acceptedShellIds = {for (final s in acceptedShells) s.id};

          final acceptedPages = <EditorPageConfig>[];
          for (final page in candidate.pageCatalog.pages) {
            if (page.shellId != null &&
                !acceptedShellIds.contains(page.shellId)) {
              allRejected.add(
                PatchRejectedEntry(
                  section: 'pageCatalog',
                  key: page.id,
                  message:
                      'La page "${page.id}" référence un shell inconnu ou rejeté ("${page.shellId}").',
                  rawValue: rawPagesById[page.id] ?? page.toJson(),
                ),
              );
              continue;
            }
            final trialCatalog = EditorPageCatalog(
              pages: [...acceptedPages, page],
              shells: acceptedShells,
            );
            try {
              validateAppearance(candidate.copyWith(pageCatalog: trialCatalog));
              acceptedPages.add(page);
            } catch (pageError) {
              allRejected.add(
                PatchRejectedEntry(
                  section: 'pageCatalog',
                  key: page.id,
                  message: pageError is FormatException
                      ? pageError.message
                      : pageError.toString(),
                  rawValue: rawPagesById[page.id] ?? page.toJson(),
                ),
              );
            }
          }

          String? resolvedHomeId;
          final candidateHomeId = candidate.pageCatalog.homePageId;
          if (candidateHomeId != null &&
              acceptedPages.any((p) => p.id == candidateHomeId)) {
            try {
              validateAppearance(
                candidate.copyWith(
                  pageCatalog: EditorPageCatalog(
                    pages: acceptedPages,
                    shells: acceptedShells,
                    homePageId: candidateHomeId,
                  ),
                ),
              );
              resolvedHomeId = candidateHomeId;
            } catch (homeError) {
              allRejected.add(
                PatchRejectedEntry(
                  section: 'pageCatalog',
                  key: 'homePageId',
                  message: homeError is FormatException
                      ? homeError.message
                      : homeError.toString(),
                  rawValue: candidateHomeId,
                ),
              );
            }
          }
          if (resolvedHomeId == null) {
            final prevHomeId = workingAppearance.pageCatalog.homePageId;
            if (prevHomeId != null &&
                acceptedPages.any((p) => p.id == prevHomeId)) {
              try {
                validateAppearance(
                  candidate.copyWith(
                    pageCatalog: EditorPageCatalog(
                      pages: acceptedPages,
                      shells: acceptedShells,
                      homePageId: prevHomeId,
                    ),
                  ),
                );
                resolvedHomeId = prevHomeId;
              } catch (_) {
                resolvedHomeId = null;
              }
            }
          }

          String? resolvedRootShellId;
          final candidateRootShellId = candidate.pageCatalog.rootShellId;
          if (candidateRootShellId != null &&
              acceptedShellIds.contains(candidateRootShellId)) {
            try {
              validateAppearance(
                candidate.copyWith(
                  pageCatalog: EditorPageCatalog(
                    pages: acceptedPages,
                    shells: acceptedShells,
                    homePageId: resolvedHomeId,
                    rootShellId: candidateRootShellId,
                  ),
                ),
              );
              resolvedRootShellId = candidateRootShellId;
            } catch (rootShellError) {
              allRejected.add(
                PatchRejectedEntry(
                  section: 'pageCatalog',
                  key: 'rootShellId',
                  message: rootShellError is FormatException
                      ? rootShellError.message
                      : rootShellError.toString(),
                  rawValue: candidateRootShellId,
                ),
              );
            }
          }
          if (resolvedRootShellId == null) {
            final prevRootShellId = workingAppearance.pageCatalog.rootShellId;
            if (prevRootShellId != null &&
                acceptedShellIds.contains(prevRootShellId)) {
              try {
                validateAppearance(
                  candidate.copyWith(
                    pageCatalog: EditorPageCatalog(
                      pages: acceptedPages,
                      shells: acceptedShells,
                      homePageId: resolvedHomeId,
                      rootShellId: prevRootShellId,
                    ),
                  ),
                );
                resolvedRootShellId = prevRootShellId;
              } catch (_) {
                resolvedRootShellId = null;
              }
            }
          }

          final salvagedCatalog =
              acceptedPages.length ==
                      workingAppearance.pageCatalog.pages.length &&
                  acceptedShells.length ==
                      workingAppearance.pageCatalog.shells.length &&
                  resolvedHomeId == workingAppearance.pageCatalog.homePageId &&
                  resolvedRootShellId ==
                      workingAppearance.pageCatalog.rootShellId &&
                  _samePageList(
                    acceptedPages,
                    workingAppearance.pageCatalog.pages,
                  ) &&
                  _sameShellList(
                    acceptedShells,
                    workingAppearance.pageCatalog.shells,
                  )
              ? workingAppearance.pageCatalog
              : EditorPageCatalog(
                  pages: acceptedPages,
                  shells: acceptedShells,
                  homePageId: resolvedHomeId,
                  rootShellId: resolvedRootShellId,
                );
          final salvagedCandidate = candidate.copyWith(
            pageCatalog: salvagedCatalog,
          );

          try {
            validateAppearance(salvagedCandidate);
            candidate = salvagedCandidate;
            if (identical(salvagedCatalog, workingAppearance.pageCatalog)) {
              appliedPatch.remove('pageCatalog');
            } else {
              appliedPatch['pageCatalog'] = salvagedCatalog.toJson();
            }
          } catch (_) {
            final reverted = candidate.copyWith(
              pageCatalog: workingAppearance.pageCatalog,
            );
            appliedPatch.remove('pageCatalog');
            if (!allRejected.any((entry) => entry.section == 'pageCatalog')) {
              allRejected.add(
                PatchRejectedEntry(
                  section: 'pageCatalog',
                  key: 'pageCatalog',
                  message: error is FormatException
                      ? error.message
                      : error.toString(),
                  rawValue: rawPageCatalog,
                ),
              );
            }
            try {
              validateAppearance(reverted);
              candidate = reverted;
            } catch (_) {
              return VibeSalvageOutcome.none(
                workingAppearance,
                rejectedEntries: allRejected,
                wasTruncated: wasTruncated,
                interruptedSection: interruptedSection,
                interruptedKey: interruptedKey,
              );
            }
          }
        } else {
          return VibeSalvageOutcome.none(
            workingAppearance,
            rejectedEntries: allRejected,
            wasTruncated: wasTruncated,
            interruptedSection: interruptedSection,
            interruptedKey: interruptedKey,
          );
        }
      }
    }

    final rawStylesInPatch = effectiveVibePatch == null
        ? null
        : (effectiveVibePatch['data'] is Map
              ? (effectiveVibePatch['data'] as Map)['styles']
              : effectiveVibePatch['styles']);
    final patchedStyleIds = rawStylesInPatch is Map
        ? rawStylesInPatch.keys.whereType<String>().toSet()
        : const <String>{};
    final layoutStyleViolations =
        AppearanceTransfer.findIneffectiveLayoutStyleViolations(
          candidate,
          previous: workingAppearance,
          patchedStyleIds: patchedStyleIds.isEmpty ? null : patchedStyleIds,
        );
    if (layoutStyleViolations.isNotEmpty) {
      final adjustedStyles = Map<String, ContainerStyle>.of(candidate.styles);
      final appliedStyles = appliedPatch['styles'] is Map<String, Object?>
          ? Map<String, Object?>.of(
              appliedPatch['styles'] as Map<String, Object?>,
            )
          : null;
      for (final entry in layoutStyleViolations.entries) {
        final styleId = entry.key;
        final previousStyle = workingAppearance.styles[styleId];
        if (previousStyle != null) {
          adjustedStyles[styleId] = previousStyle;
        } else {
          adjustedStyles.remove(styleId);
        }
        appliedStyles?.remove(styleId);
        allRejected.add(
          PatchRejectedEntry(
            section: 'styles',
            key: styleId,
            message: entry.value,
            rawValue: rawStylesInPatch is Map ? rawStylesInPatch[styleId] : null,
          ),
        );
      }
      candidate = candidate.copyWith(styles: adjustedStyles);
      if (appliedStyles != null) {
        if (appliedStyles.isEmpty) {
          appliedPatch.remove('styles');
        } else {
          appliedPatch['styles'] = appliedStyles;
        }
      }
    }

    final reachableIds = computeReachableIds(
      baseForScope: workingAppearance,
      next: candidate,
      scope: scope,
      instantiatedIds: instantiatedIds,
      initialPageIds: initialPageIds,
      hasRegistry: hasRegistry,
      requireNewPageComponent: true,
    );

    final rawComponentsInPatch = effectiveVibePatch == null
        ? null
        : (effectiveVibePatch['data'] is Map
              ? (effectiveVibePatch['data'] as Map)['components']
              : effectiveVibePatch['components']);
    final patchTouchedComponents =
        rawComponentsInPatch is Map && rawComponentsInPatch.isNotEmpty;

    final hasReachableComponentChanges = _hasReachableComponentOrPageChanges(
      previous: workingAppearance,
      next: candidate,
      reachableIds: reachableIds,
    );

    final hasReachableScreenChanges = patchTouchedComponents
        ? hasReachableComponentChanges
        : _hasReachableChanges(
            previous: workingAppearance,
            next: candidate,
            reachableIds: reachableIds,
          );

    final hasRejectedReachableParentWithValidPeers =
        candidate != workingAppearance &&
        allRejected.any(
          (entry) =>
              entry.section == 'components' && reachableIds.contains(entry.key),
        );

    final hasTruncatedProgress =
        wasTruncated &&
        (appliedPatch.isNotEmpty || appliedRepoKeys.isNotEmpty) &&
        (candidate != workingAppearance || appliedRepoKeys.isNotEmpty);

    if (!hasReachableScreenChanges &&
        !hasRejectedReachableParentWithValidPeers &&
        !hasTruncatedProgress) {
      return VibeSalvageOutcome.none(
        workingAppearance,
        rejectedEntries: allRejected,
        wasTruncated: wasTruncated,
        interruptedSection: interruptedSection,
        interruptedKey: interruptedKey,
      );
    }

    final detachedIds = <String>[
      for (final id in candidate.components.keys)
        if (!initialAppearance.components.containsKey(id) &&
            !reachableIds.contains(id))
          id,
    ];

    final missingPlacedIds = _findNewlyPlacedMissingComponents(
      previous: workingAppearance,
      next: candidate,
      reachableIds: reachableIds,
    );

    final pendingRequired = <String>{
      for (final rejected in allRejected)
        if (rejected.section == 'components' &&
            (reachableIds.contains(rejected.key) ||
                workingAppearance.components.containsKey(rejected.key)))
          rejected.key,
      if (wasTruncated &&
          interruptedSection == 'components' &&
          interruptedKey != null &&
          interruptedKey.isNotEmpty &&
          reachableIds.contains(interruptedKey))
        interruptedKey,
      if (wasTruncated) ...missingPlacedIds,
    };

    return VibeSalvageOutcome(
      hasCheckpoint: true,
      checkpointAppearance: candidate,
      rejectedEntries: List<PatchRejectedEntry>.unmodifiable(allRejected),
      detachedComponentIds: List<String>.unmodifiable(detachedIds),
      missingPlacedComponentIds: List<String>.unmodifiable(missingPlacedIds),
      pendingRequiredComponentIds: Set<String>.unmodifiable(pendingRequired),
      requiresScreenAttachment:
          !hasReachableScreenChanges && detachedIds.isNotEmpty,
      wasTruncated: wasTruncated,
      interruptedSection: interruptedSection,
      interruptedKey: interruptedKey,
    );
  }

  /// Nettoie à la validation finale tout composant brouillon non rattaché issu d'un checkpoint
  /// antérieur qui aurait été remplacé par d'autres identifiants lors du correctif delta.
  static Appearance pruneUnreachableTurnDrafts({
    required Appearance baseAppearance,
    required Appearance nextAppearance,
    required Set<String> reachableIds,
  }) {
    final staleIds = <String>{
      for (final id in nextAppearance.components.keys)
        if (!baseAppearance.components.containsKey(id) &&
            !reachableIds.contains(id))
          id,
    };
    if (staleIds.isEmpty) return nextAppearance;

    final components = Map<String, ComponentConfig>.of(nextAppearance.components)
      ..removeWhere((id, _) => staleIds.contains(id));
    final styles = Map<String, ContainerStyle>.of(nextAppearance.styles)
      ..removeWhere(
        (id, _) =>
            !baseAppearance.styles.containsKey(id) &&
            (staleIds.contains(id) ||
                (id.endsWith(':item') &&
                    staleIds.contains(id.substring(0, id.length - 5)))),
      );
    final behaviors =
        Map<String, List<ComponentBehavior>>.of(nextAppearance.behaviors)
          ..removeWhere(
            (id, _) =>
                !baseAppearance.behaviors.containsKey(id) &&
                (staleIds.contains(id) ||
                    (id.endsWith(':item') &&
                        staleIds.contains(id.substring(0, id.length - 5)))),
          );
    final usages = Map<String, ComponentUsage>.of(nextAppearance.usages)
      ..removeWhere(
        (id, _) =>
            !baseAppearance.usages.containsKey(id) && staleIds.contains(id),
      );

    return nextAppearance.copyWith(
      components: components,
      styles: styles,
      behaviors: behaviors,
      usages: usages,
    );
  }

  /// Construit le prompt de relance delta s'appuyant sur l'`ÉTAT ACTUEL` déjà mis à jour.
  static String buildDeltaRetryPrompt({
    required String refreshedTurnPrompt,
    required List<String> priorCauses,
    required VibeSalvageOutcome salvage,
    required Set<String> pendingRequiredComponentIds,
  }) {
    final buffer = StringBuffer()
      ..writeln(refreshedTurnPrompt)
      ..writeln()
      ..writeln('CORRECTION REQUISE (MODE DELTA INCRÉMENTAL) :')
      ..writeln(
        'Les composants, styles, comportements et repositories valides déjà générés '
        'lors de la tentative précédente ont DÉJÀ été conservés et intégrés dans '
        'l’ÉTAT ACTUEL (ou ÉTAT DU SCOPE CIBLÉ) ci-dessus.',
      )
      ..writeln('CONSIGNES STRICTES DE RELANCE RAPIDE :')
      ..writeln(
        '- NE RÉGÉNÈRE PAS toute la page : ne réémets aucun composant, style ou repository '
        'déjà présent et valide dans l’ÉTAT ACTUEL.',
      )
      ..writeln(
        '- Renvoie UNIQUEMENT un objet JSON {"message":"...","vibe":{...}} contenant le '
        'patch minimal nécessaire pour corriger ou compléter les éléments listés ci-dessous.',
      )
      ..writeln(
        '- Rappel : si tu modifies la clé "placements" d’un conteneur existant, réémets '
        'l’intégralité des zones/régions et des slots existants de ce conteneur à conserver.',
      );

    if (priorCauses.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Cause(s) de l’échec précédent :');
      for (final cause in priorCauses) {
        buffer.writeln('- $cause');
      }
    }

    if (salvage.wasTruncated) {
      final activeInfo = salvage.interruptedKey != null
          ? ' (coupé pendant la réception de ${salvage.interruptedSection ?? "vibe"}["${salvage.interruptedKey}"])'
          : '';
      buffer
        ..writeln()
        ..writeln(
          'Flux interrompu avant la fin du JSON$activeInfo : '
          'complète uniquement la fin manquante de l’écran à partir de l’ÉTAT ACTUEL.',
        );
    }

    if (salvage.rejectedEntries.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Entrées rejetées à corriger dans ton patch delta :');
      for (final entry in salvage.rejectedEntries) {
        final snippet = _boundedJsonSnippet(entry.rawValue);
        buffer.writeln(
          '- ${entry.section}["${entry.key}"] : ${entry.message}'
          '${snippet == null ? '' : ' | JSON reçu : $snippet'}',
        );
      }
      if (salvage.rejectedEntries.any((e) => e.section == 'pageCatalog')) {
        buffer
          ..writeln()
          ..writeln(
            'Rappel sur "pageCatalog" : la route "/" est déjà réservée par la page racine '
            '("root" / "mainLayout"). Ne déclare JAMAIS une page avec "path": "/" dans '
            '"pageCatalog" ; configure directement "root" / "mainLayout" pour "/", ou donne '
            'à chaque nouvelle page un chemin distinct (ex. "/accueil", "/clients") sans "/" '
            'final, sans espace, sans "?" et sans "#".',
          );
      }
    }

    final missingDefs = <String>{
      ...salvage.missingPlacedComponentIds,
      ...pendingRequiredComponentIds,
    };
    if (missingDefs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Composants requis à définir ou corriger dans "components" : '
          '${missingDefs.map((id) => '"$id"').join(', ')}.',
        );
    }

    if (salvage.detachedComponentIds.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          'Composants déjà enregistrés dans "components" en attente de rattachement '
          '(réutilisables directement par leur id dans les "placements" du parent sans les redéclarer, '
          'ou supprimables avec null s’ils sont superflus) : '
          '${salvage.detachedComponentIds.map((id) => '"$id"').join(', ')}.',
        );
    }

    return buffer.toString();
  }

  static String? _boundedJsonSnippet(Object? rawValue, {int maxChars = 600}) {
    if (rawValue == null) return null;
    String encoded;
    try {
      encoded = jsonEncode(rawValue);
    } catch (_) {
      encoded = rawValue.toString();
    }
    if (encoded.length <= maxChars) return encoded;
    return '${encoded.substring(0, maxChars)}…';
  }

  static bool _samePageList(
    List<EditorPageConfig> a,
    List<EditorPageConfig> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameShellList(
    List<EditorShellConfig> a,
    List<EditorShellConfig> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _hasReachableComponentOrPageChanges({
    required Appearance previous,
    required Appearance next,
    required Set<String> reachableIds,
  }) {
    if (!_samePageList(previous.pageCatalog.pages, next.pageCatalog.pages) ||
        !_sameShellList(
          previous.pageCatalog.shells,
          next.pageCatalog.shells,
        ) ||
        previous.pageCatalog.homePageId != next.pageCatalog.homePageId ||
        previous.pageCatalog.rootShellId != next.pageCatalog.rootShellId) {
      return true;
    }
    for (final id in reachableIds) {
      if (previous.components[id] != next.components[id]) {
        return true;
      }
    }
    return false;
  }

  static bool _hasReachableChanges({
    required Appearance previous,
    required Appearance next,
    required Set<String> reachableIds,
  }) {
    if (previous.mode != next.mode ||
        previous.accent != next.accent ||
        previous.backgroundOpacity != next.backgroundOpacity ||
        previous.windowOpacity != next.windowOpacity ||
        previous.windowEffect != next.windowEffect ||
        previous.bindingDebounceMs != next.bindingDebounceMs ||
        previous.bindingSaveOnBlurOnly != next.bindingSaveOnBlurOnly ||
        !_samePageList(previous.pageCatalog.pages, next.pageCatalog.pages) ||
        !_sameShellList(
          previous.pageCatalog.shells,
          next.pageCatalog.shells,
        ) ||
        previous.pageCatalog.homePageId != next.pageCatalog.homePageId ||
        previous.pageCatalog.rootShellId != next.pageCatalog.rootShellId) {
      return true;
    }

    for (final id in reachableIds) {
      if (previous.components[id] != next.components[id]) {
        return true;
      }
      if (previous.styles[id] != next.styles[id] ||
          previous.styles['$id:item'] != next.styles['$id:item']) {
        return true;
      }
      if (!_sameBehaviorList(previous.behaviors[id], next.behaviors[id]) ||
          !_sameBehaviorList(
            previous.behaviors['$id:item'],
            next.behaviors['$id:item'],
          )) {
        return true;
      }
      if (previous.usages[id] != next.usages[id]) {
        return true;
      }
    }

    if (previous.styles['background'] != next.styles['background']) {
      return true;
    }
    return false;
  }

  static bool _sameBehaviorList(
    List<ComponentBehavior>? a,
    List<ComponentBehavior>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return (a?.isEmpty ?? true) && (b?.isEmpty ?? true);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<String> _findNewlyPlacedMissingComponents({
    required Appearance previous,
    required Appearance next,
    required Set<String> reachableIds,
  }) {
    final previousTypes = _collectSlotTypesOfContainers(previous, reachableIds);
    final nextTypes = _collectSlotTypesOfContainers(next, reachableIds);
    final missing = <String>[];

    for (final entry in nextTypes.entries) {
      final slotId = entry.key;
      if (slotId == 'scaffold:body' || slotId == 'scaffold:outlet') continue;
      if (next.components.containsKey(slotId)) continue;
      if (previousTypes.containsKey(slotId) &&
          !previous.components.containsKey(slotId)) {
        continue;
      }
      final rawType = entry.value;
      final normalized = JsonComponentType.normalize(rawType, id: slotId);
      final short = JsonComponentType.shortName(normalized);
      if (_configurableShortTypes.contains(short)) {
        missing.add(slotId);
      }
    }
    return missing;
  }

  static Map<String, String> _collectSlotTypesOfContainers(
    Appearance appearance,
    Set<String> containerIds,
  ) {
    final result = <String, String>{};
    for (final id in containerIds) {
      final config = appearance.components[id];
      if (config == null) continue;
      switch (config) {
        case final SuperLayoutConfig layout:
          for (final childId in layout.placedSlotIds) {
            result.putIfAbsent(childId, () => layout.slotTypeOf(childId));
          }
        case final SuperListViewConfig list:
          for (final childId in list.template.placedSlotIds) {
            result.putIfAbsent(
              childId,
              () => list.template.slotTypeOf(childId),
            );
          }
        case final SuperTabConfig tab:
          for (final childId in tab.placedSlotIds) {
            result.putIfAbsent(childId, () => tab.slotTypeOf(childId));
          }
        case final SuperConditionalConfig cond:
          for (final childId in cond.placedSlotIds) {
            result.putIfAbsent(childId, () => cond.slotTypeOf(childId));
          }
        case final SuperTreeViewConfig tree:
          for (final childId in tree.placedSlotIds) {
            result.putIfAbsent(childId, () => tree.slotTypeOf(childId));
          }
        case final SuperTableConfig table:
          for (final childId in table.placedSlotIds) {
            result.putIfAbsent(childId, () => table.slotTypeOf(childId));
          }
        case final NativeComponentConfig native:
          for (final childId in native.placements.values.expand((ids) => ids)) {
            result.putIfAbsent(childId, () => native.slotTypeOf(childId));
          }
        case final ScaffoldPageConfig scaffold:
          for (final childId in scaffold.native.placements.values.expand(
            (ids) => ids,
          )) {
            result.putIfAbsent(
              childId,
              () => scaffold.native.slotTypeOf(childId),
            );
          }
        case final A4PageConfig a4:
          for (final entry in a4.childSlots.entries) {
            result.putIfAbsent(entry.key, () => entry.value);
          }
        default:
          break;
      }
    }
    return result;
  }
}
