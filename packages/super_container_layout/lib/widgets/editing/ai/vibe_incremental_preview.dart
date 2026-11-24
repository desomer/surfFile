/// Applicateur incrémental d'aperçu en streaming ([VibeIncrementalPreviewApplier])
/// pour l'assistant Vibe IA.
///
/// Évite de ré-encoder (`jsonEncode`) et de re-décoder l'intégralité du patch
/// cumulé à chaque palier de 250 ms : seules les entrées nouvellement reçues
/// (ainsi que les éventuelles entrées différées en attente d'un parent, d'un
/// scope ou d'une validation de région/catalogue) sont décodées et fusionnées
/// sur l'[Appearance] d'aperçu courante.
library;

import 'package:flutter/foundation.dart' show immutable, mapEquals, visibleForTesting;

import '../../../ai/vibe_stream_parser.dart';
import '../../../models/component_behavior.dart';
import '../../../models/component_config.dart';
import '../../../models/component_usage.dart';
import '../../../models/super_layout_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../services/inspection/vibe_app_inspector.dart'
    show VibeVisibleViewportSnapshot;
import '../../../theme/appearance.dart';
import '../../../theme/container_style.dart';
import '../slots/editor_context_menu.dart';
import 'vibe_repository_applier.dart';
import 'vibe_scope_helpers.dart';

/// Résultat d'une étape d'application incrémentale de patch Vibe en streaming.
@immutable
class VibeIncrementalPreviewStepResult {
  /// Construit le résultat d'un palier d'aperçu incrémental.
  const VibeIncrementalPreviewStepResult({
    required this.appearance,
    required this.effectiveStepPatch,
    required this.rejectedEntries,
    required this.didChangeAppearance,
    required this.decodedEntryCount,
  });

  /// Apparence résultante après fusion des deltas valides du palier.
  final Appearance appearance;

  /// Sous-patch effectif traité lors de ce palier (utilisé pour le routage live et le diagnostic).
  final Map<String, dynamic> effectiveStepPatch;

  /// Entrées rejetées lors de ce palier et conservées en attente des prochains fragments.
  final List<PatchRejectedEntry> rejectedEntries;

  /// Indique si [appearance] diffère de l'apparence d'aperçu précédente.
  final bool didChangeAppearance;

  /// Nombre d'entrées JSON effectivement passées au décodeur lors de ce palier.
  final int decodedEntryCount;
}

@immutable
class _EntrySlotKey {
  const _EntrySlotKey(this.section, this.key);

  final String? section;
  final String key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EntrySlotKey && other.section == section && other.key == key;

  @override
  int get hashCode => Object.hash(section, key);
}

/// Accumulateur à état appliquant incrémentalement les paliers SSE d'un tour Vibe IA.
///
/// Garantit l'équivalence avec une application cumulative depuis [baseAppearance]
/// tout en réduisant le décodage JSON à $O(\Delta)$ par palier de 250 ms :
/// - réécriture incrémentale des alias de repositories ([aliasToActualId]) ;
/// - conservation des contraintes directes d'enfant (`slotSizeConstraints`) reçues
///   avant le conteneur parent qui place le slot ;
/// - ré-évaluation automatique des entrées temporairement hors-scope ou rejetées.
class VibeIncrementalPreviewApplier {
  /// Crée un applicateur incrémental ancré sur [baseAppearance].
  VibeIncrementalPreviewApplier({
    required Appearance baseAppearance,
    this.codec = const AppearanceCodec(),
  }) : _baseAppearance = baseAppearance,
       _workingAppearance = baseAppearance;

  /// Codec d'apparence utilisé pour le décodage partiel.
  final AppearanceCodec codec;

  Appearance _baseAppearance;
  Appearance _workingAppearance;

  int _lastRewrittenRevision = 0;
  Map<String, String> _lastAliasMap = const <String, String>{};
  final Map<String, Object?> _rewrittenRoot = <String, Object?>{};
  final Map<String, Map<String, Object?>> _rewrittenSections =
      <String, Map<String, Object?>>{};

  final Map<_EntrySlotKey, Object?> _appliedEntries = <_EntrySlotKey, Object?>{};
  final Map<String, SlotSizeConstraints> _selfConstraintsBySlotId =
      <String, SlotSizeConstraints>{};

  int _totalDecodedEntries = 0;

  /// Apparence de base courante servant de point de référence (ex. `checkpointAppearance`).
  Appearance get baseAppearance => _baseAppearance;

  /// Dernière apparence d'aperçu valide produite par cet applicateur.
  Appearance get currentAppearance => _workingAppearance;

  /// Nombre cumulé d'entrées décodées depuis le dernier [reset] (exposé pour les tests).
  @visibleForTesting
  int get debugTotalDecodedEntries => _totalDecodedEntries;

  /// Réinitialise complètement l'état incrémental sur [newBaseAppearance].
  void reset(Appearance newBaseAppearance) {
    _baseAppearance = newBaseAppearance;
    _workingAppearance = newBaseAppearance;
    _lastRewrittenRevision = 0;
    _lastAliasMap = const <String, String>{};
    _rewrittenRoot.clear();
    _rewrittenSections.clear();
    _appliedEntries.clear();
    _selfConstraintsBySlotId.clear();
    _totalDecodedEntries = 0;
  }

  /// Construit le patch cumulatif réécrit à jour à partir de [snapshot] et [aliasToActualId].
  Map<String, dynamic>? buildEffectiveCumulativePatch({
    required VibeStreamSnapshot snapshot,
    Map<String, String> aliasToActualId = const <String, String>{},
    VibeChatScope? scope,
    VibeVisibleViewportSnapshot? visibleViewportSnapshot,
  }) {
    final rawPatch = snapshot.partialVibePatch;
    if (rawPatch == null) return null;

    Map<String, dynamic> cumulative;
    if (aliasToActualId.isEmpty && _lastAliasMap.isEmpty) {
      cumulative = rawPatch;
    } else {
      if (!mapEquals(_lastAliasMap, aliasToActualId)) {
        _lastAliasMap = Map<String, String>.unmodifiable(aliasToActualId);
        _lastRewrittenRevision = 0;
        _rewrittenRoot.clear();
        _rewrittenSections.clear();
      }
      final entries = snapshot.patchEntries;
      if (entries.isNotEmpty && _lastRewrittenRevision < snapshot.patchRevision) {
        for (final entry in entries) {
          if (entry.revision <= _lastRewrittenRevision) continue;
          final rewrittenValue = _rewriteSingleEntryValue(
            section: entry.section,
            key: entry.key,
            value: entry.value,
            aliasToActualId: aliasToActualId,
          );
          if (entry.section case final section?) {
            final map = _rewrittenSections.putIfAbsent(
              section,
              () => <String, Object?>{},
            );
            map[entry.key] = rewrittenValue;
          } else {
            _rewrittenRoot[entry.key] = rewrittenValue;
          }
          _lastRewrittenRevision = entry.revision;
        }
        cumulative = <String, dynamic>{
          ..._rewrittenRoot,
          for (final sectionEntry in _rewrittenSections.entries)
            if (sectionEntry.value.isNotEmpty)
              sectionEntry.key: sectionEntry.value,
        };
      } else if (entries.isEmpty) {
        cumulative = VibeRepositoryApplier.rewriteVibePatchBindings(
          rawPatch,
          aliasToActualId,
        );
      } else {
        cumulative = <String, dynamic>{
          ..._rewrittenRoot,
          for (final sectionEntry in _rewrittenSections.entries)
            if (sectionEntry.value.isNotEmpty)
              sectionEntry.key: sectionEntry.value,
        };
      }
    }

    var effective = scope == null
        ? cumulative
        : VibeScopeHelpers.filterPatchToScope(_baseAppearance, cumulative, scope);
    if (visibleViewportSnapshot != null) {
      effective = VibeScopeHelpers.filterPatchToVisibleViewport(
        _baseAppearance,
        effective,
        visibleViewportSnapshot,
      );
    }
    return effective;
  }

  /// Applique incrémentalement les changements de [snapshot] (ou [rawCumulativePatch])
  /// par rapport au palier précédent.
  ///
  /// Retourne `null` lorsque le patch filtré ne contient aucune modification applicable.
  VibeIncrementalPreviewStepResult? applyStep({
    VibeStreamSnapshot? snapshot,
    Map<String, dynamic>? rawCumulativePatch,
    Map<String, String> aliasToActualId = const <String, String>{},
    VibeChatScope? scope,
    VibeVisibleViewportSnapshot? visibleViewportSnapshot,
    void Function(Appearance appearance)? validateAppearance,
  }) {
    if (snapshot == null && rawCumulativePatch == null) return null;

    final Map<String, dynamic>? effectiveCumulative;
    if (snapshot != null) {
      effectiveCumulative = buildEffectiveCumulativePatch(
        snapshot: snapshot,
        aliasToActualId: aliasToActualId,
        scope: scope,
        visibleViewportSnapshot: visibleViewportSnapshot,
      );
    } else {
      var candidate = aliasToActualId.isEmpty
          ? rawCumulativePatch!
          : VibeRepositoryApplier.rewriteVibePatchBindings(
              rawCumulativePatch!,
              aliasToActualId,
            );
      if (scope != null) {
        candidate = VibeScopeHelpers.filterPatchToScope(
          _baseAppearance,
          candidate,
          scope,
        );
      }
      if (visibleViewportSnapshot != null) {
        candidate = VibeScopeHelpers.filterPatchToVisibleViewport(
          _baseAppearance,
          candidate,
          visibleViewportSnapshot,
        );
      }
      effectiveCumulative = candidate;
    }

    if (effectiveCumulative == null || !_hasAnyEntry(effectiveCumulative)) {
      return null;
    }

    final payload = effectiveCumulative['data'] is Map<String, dynamic>
        ? effectiveCumulative['data'] as Map<String, dynamic>
        : effectiveCumulative;

    final targetEntries = <_EntrySlotKey, Object?>{};
    for (final entry in payload.entries) {
      final topKey = entry.key;
      if (topKey == 'version' ||
          topKey == 'vibe' ||
          topKey == 'merge' ||
          topKey == 'format' ||
          topKey == 'groups' ||
          topKey == 'verifyRender') {
        continue;
      }
      if (_sectionNames.contains(topKey)) {
        final sectionMap = entry.value;
        if (sectionMap is Map) {
          for (final sub in sectionMap.entries) {
            if (sub.key is String && (sub.key as String).trim().isNotEmpty) {
              targetEntries[_EntrySlotKey(topKey, sub.key as String)] =
                  sub.value;
            }
          }
        } else if (sectionMap != null) {
          targetEntries[_EntrySlotKey(topKey, topKey)] = sectionMap;
        }
      } else {
        targetEntries[_EntrySlotKey(null, topKey)] = entry.value;
      }
    }

    if (targetEntries.isEmpty) return null;

    // Si une suppression (`value == null`) déjà appliquée disparaît ou est remplacée,
    // repart proprement de `_baseAppearance` pour restaurer les placements parents purgés.
    var needsFullReset = false;
    final revertedKeys = <_EntrySlotKey>[];
    for (final appliedEntry in _appliedEntries.entries) {
      final slotKey = appliedEntry.key;
      if (!targetEntries.containsKey(slotKey)) {
        if (appliedEntry.value == null) {
          needsFullReset = true;
          break;
        }
        revertedKeys.add(slotKey);
      } else if (appliedEntry.value == null &&
          !identical(targetEntries[slotKey], appliedEntry.value)) {
        needsFullReset = true;
        break;
      }
    }

    if (needsFullReset) {
      _workingAppearance = _baseAppearance;
      _appliedEntries.clear();
      _selfConstraintsBySlotId.clear();
      revertedKeys.clear();
    } else if (revertedKeys.isNotEmpty) {
      for (final key in revertedKeys) {
        _workingAppearance = _restoreSingleKeyFromBase(_workingAppearance, key);
        _appliedEntries.remove(key);
        if (key.section == 'components') {
          _selfConstraintsBySlotId.remove(key.key);
        }
      }
    }

    final deltaRoot = <String, Object?>{};
    final deltaSections = <String, Map<String, Object?>>{};
    var deltaCount = 0;
    var hasNewSelfConstraint = false;
    var hasComponentDelta = false;

    for (final entry in targetEntries.entries) {
      final slotKey = entry.key;
      final nextVal = entry.value;
      if (_appliedEntries.containsKey(slotKey) &&
          identical(_appliedEntries[slotKey], nextVal)) {
        continue;
      }
      if (_appliedEntries.containsKey(slotKey)) {
        _workingAppearance = _restoreSingleKeyFromBase(
          _workingAppearance,
          slotKey,
        );
        _appliedEntries.remove(slotKey);
        if (slotKey.section == 'components') {
          _selfConstraintsBySlotId.remove(slotKey.key);
        }
      }

      if (slotKey.section case final section?) {
        (deltaSections[section] ??= <String, Object?>{})[slotKey.key] = nextVal;
        if (section == 'components') {
          hasComponentDelta = true;
          if (nextVal is Map) {
            final rawConstraints = nextVal['slotSizeConstraints'];
            if (SlotSizeConstraints.isDirectConstraintsMap(rawConstraints)) {
              try {
                _selfConstraintsBySlotId[slotKey.key] =
                    SlotSizeConstraints.fromJson(rawConstraints);
                hasNewSelfConstraint = true;
              } on FormatException {
                // Laissé au rejet standard de patchFromJsonPartial.
              }
            }
          } else if (nextVal == null) {
            _selfConstraintsBySlotId.remove(slotKey.key);
          }
        }
      } else {
        deltaRoot[slotKey.key] = nextVal;
      }
      deltaCount++;
    }

    if (deltaCount == 0 && revertedKeys.isEmpty && !needsFullReset) {
      return VibeIncrementalPreviewStepResult(
        appearance: _workingAppearance,
        effectiveStepPatch: const <String, dynamic>{},
        rejectedEntries: const <PatchRejectedEntry>[],
        didChangeAppearance: false,
        decodedEntryCount: 0,
      );
    }

    final deltaPatch = <String, dynamic>{
      ...deltaRoot,
      for (final sec in deltaSections.entries) sec.key: sec.value,
    };

    final prevWorking = _workingAppearance;
    var nextAppearance = _workingAppearance;
    var rejected = const <PatchRejectedEntry>[];

    if (deltaCount > 0) {
      _totalDecodedEntries += deltaCount;
      final partial = AppearanceTransfer.applyVibeMapPartial(
        _workingAppearance,
        deltaPatch,
        codec: codec,
      );
      nextAppearance = partial.appearance;
      rejected = partial.rejectedEntries;

      // Rétablit depuis `_baseAppearance` tout composant pré-accepté à un palier
      // antérieur mais désormais rejeté après arrivée du `slotTypes` parent.
      if (rejected.isNotEmpty) {
        Map<String, ComponentConfig>? repairedComponents;
        for (final rej in rejected) {
          final rejKey = _EntrySlotKey(
            rej.section == 'root' || rej.section == 'pageCatalog' || rej.section == 'responsiveLayout'
                ? null
                : rej.section,
            rej.key,
          );
          _appliedEntries.remove(rejKey);
          if (rej.section == 'components') {
            final baseComp = _baseAppearance.components[rej.key];
            if (nextAppearance.components[rej.key] != baseComp) {
              repairedComponents ??= Map<String, ComponentConfig>.of(
                nextAppearance.components,
              );
              if (baseComp == null) {
                repairedComponents.remove(rej.key);
              } else {
                repairedComponents[rej.key] = baseComp;
              }
            }
          }
        }
        if (repairedComponents != null) {
          nextAppearance = nextAppearance.copyWith(
            components: repairedComponents,
          );
        }
      }

      // Enregistre les entrées effectivement acceptées dans ce delta.
      final appliedPatch = partial.appliedPatch;
      for (final entry in appliedPatch.entries) {
        if (_sectionNames.contains(entry.key) && entry.value is Map) {
          final secMap = entry.value as Map;
          for (final subKey in secMap.keys) {
            if (subKey is String) {
              final slotKey = _EntrySlotKey(entry.key, subKey);
              if (targetEntries.containsKey(slotKey) &&
                  nextAppearance.components.containsKey(subKey) ==
                      (entry.key != 'components'
                          ? nextAppearance.components.containsKey(subKey)
                          : targetEntries[slotKey] != null)) {
                _appliedEntries[slotKey] = targetEntries[slotKey];
              } else if (entry.key != 'components' &&
                  targetEntries.containsKey(slotKey)) {
                _appliedEntries[slotKey] = targetEntries[slotKey];
              }
            }
          }
        } else {
          final slotKey = _EntrySlotKey(null, entry.key);
          if (targetEntries.containsKey(slotKey)) {
            _appliedEntries[slotKey] = targetEntries[slotKey];
          }
        }
      }
    }

    if (_selfConstraintsBySlotId.isNotEmpty &&
        (hasComponentDelta || hasNewSelfConstraint)) {
      nextAppearance = AppearanceCodec.applyDirectSlotSizeConstraints(
        nextAppearance,
        _selfConstraintsBySlotId,
      );
    }

    nextAppearance = AppearanceTransfer.preserveBoundUsages(
      _baseAppearance,
      nextAppearance,
    );

    if (validateAppearance != null) {
      try {
        validateAppearance(nextAppearance);
      } catch (_) {
        if (nextAppearance.pageCatalog != prevWorking.pageCatalog) {
          nextAppearance = nextAppearance.copyWith(
            pageCatalog: prevWorking.pageCatalog,
          );
          _appliedEntries.remove(const _EntrySlotKey(null, 'pageCatalog'));
          validateAppearance(nextAppearance);
        } else {
          rethrow;
        }
      }
    }

    final changed = nextAppearance != prevWorking;
    _workingAppearance = nextAppearance;
    return VibeIncrementalPreviewStepResult(
      appearance: nextAppearance,
      effectiveStepPatch: deltaPatch,
      rejectedEntries: rejected,
      didChangeAppearance: changed,
      decodedEntryCount: deltaCount,
    );
  }

  static const Set<String> _sectionNames = <String>{
    'components',
    'styles',
    'behaviors',
    'usages',
  };

  static Object? _rewriteSingleEntryValue({
    required String? section,
    required String key,
    required Object? value,
    required Map<String, String> aliasToActualId,
  }) {
    if (aliasToActualId.isEmpty || value == null) return value;
    if (section != null) {
      final wrapped = VibeRepositoryApplier.rewriteVibePatchBindings(
        <String, dynamic>{
          section: <String, Object?>{key: value},
        },
        aliasToActualId,
      );
      return (wrapped[section] as Map?)?[key];
    }
    final wrapped = VibeRepositoryApplier.rewriteVibePatchBindings(
      <String, dynamic>{key: value},
      aliasToActualId,
    );
    return wrapped[key];
  }

  Appearance _restoreSingleKeyFromBase(
    Appearance current,
    _EntrySlotKey slotKey,
  ) {
    switch (slotKey.section) {
      case 'components':
        final updated = Map<String, ComponentConfig>.of(current.components);
        final baseVal = _baseAppearance.components[slotKey.key];
        if (baseVal == null) {
          updated.remove(slotKey.key);
        } else {
          updated[slotKey.key] = baseVal;
        }
        return current.copyWith(components: updated);
      case 'styles':
        final updated = Map<String, ContainerStyle>.of(current.styles);
        final baseVal = _baseAppearance.styles[slotKey.key];
        if (baseVal == null) {
          updated.remove(slotKey.key);
        } else {
          updated[slotKey.key] = baseVal;
        }
        return current.copyWith(styles: updated);
      case 'behaviors':
        final updated = Map<String, List<ComponentBehavior>>.of(
          current.behaviors,
        );
        final baseVal = _baseAppearance.behaviors[slotKey.key];
        if (baseVal == null) {
          updated.remove(slotKey.key);
        } else {
          updated[slotKey.key] = baseVal;
        }
        return current.copyWith(behaviors: updated);
      case 'usages':
        final updated = Map<String, ComponentUsage>.of(current.usages);
        final baseVal = _baseAppearance.usages[slotKey.key];
        if (baseVal == null) {
          updated.remove(slotKey.key);
        } else {
          updated[slotKey.key] = baseVal;
        }
        return current.copyWith(usages: updated);
      case null:
        return switch (slotKey.key) {
          'mode' => current.copyWith(mode: _baseAppearance.mode),
          'accent' => current.copyWith(accent: _baseAppearance.accent),
          'backgroundOpacity' => current.copyWith(
            backgroundOpacity: _baseAppearance.backgroundOpacity,
          ),
          'windowOpacity' => current.copyWith(
            windowOpacity: _baseAppearance.windowOpacity,
          ),
          'windowEffect' => current.copyWith(
            windowEffect: _baseAppearance.windowEffect,
          ),
          'bindingDebounceMs' => current.copyWith(
            bindingDebounceMs: _baseAppearance.bindingDebounceMs,
          ),
          'bindingSaveOnBlurOnly' => current.copyWith(
            bindingSaveOnBlurOnly: _baseAppearance.bindingSaveOnBlurOnly,
          ),
          'pageCatalog' => current.copyWith(
            pageCatalog: _baseAppearance.pageCatalog,
          ),
          'responsiveLayout' => current.copyWith(
            responsiveLayout: _baseAppearance.responsiveLayout,
          ),
          _ => current,
        };
      default:
        return current;
    }
  }

  static bool _hasAnyEntry(Map<String, dynamic> patch) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    for (final entry in payload.entries) {
      if (entry.key == 'version' ||
          entry.key == 'vibe' ||
          entry.key == 'merge' ||
          entry.key == 'format' ||
          entry.key == 'groups' ||
          entry.key == 'verifyRender') {
        continue;
      }
      if (entry.value is Map) {
        if ((entry.value as Map).isNotEmpty) return true;
      } else if (entry.value != null) {
        return true;
      }
    }
    return false;
  }
}
