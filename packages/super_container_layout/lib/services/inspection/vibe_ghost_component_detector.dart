/// Détecteur de composants fantômes (orphelins non rattachés) pour les conteneurs
/// racines vides ([VibeGhostComponentDetector]).
///
/// Permet à [SuperLayout], [VibePageAuditService] et [VibeDiagnosticsInspector] de
/// détecter de manière uniforme le cas critique où un conteneur racine monté (comme
/// `mainLayout`) possède 0 slot placé alors que des composants configurés existent
/// dans [Appearance.components] sans être rattachés à aucune racine ni page.
library;

import '../../models/super_layout_config.dart';
import '../../theme/appearance.dart';
import '../../widgets/editing/ai/vibe_scope_helpers.dart';

/// Utilitaires purs de détection et de formatage des composants fantômes.
abstract final class VibeGhostComponentDetector {
  /// Clé de source stable utilisée dans `VibeDebugCapture.syncComponentDiagnostic`.
  static const String diagnosticSourceKey = 'empty_root_ghost_components';

  /// Retourne la liste des identifiants présents dans [Appearance.components]
  /// qui ne sont atteignables depuis aucune racine active (`root`, `mainLayout`,
  /// pages/shells de `pageCatalog`, [extraRootIds], [mountedRootIds]).
  static List<String> findUnreachableComponentIds(
    Appearance appearance, {
    Iterable<String> extraRootIds = const <String>[],
    Iterable<String> mountedRootIds = const <String>[],
  }) {
    if (appearance.components.isEmpty) return const <String>[];

    final roots = <String>{
      if (appearance.components.containsKey('root')) 'root',
      if (appearance.components.containsKey('mainLayout')) 'mainLayout',
      for (final page in appearance.pageCatalog.pages) page.id,
      for (final shell in appearance.pageCatalog.shells) shell.id,
      ...extraRootIds,
      ...mountedRootIds,
    };

    if (roots.isEmpty) return const <String>[];

    final reachable = <String>{};
    final pending = <String>[...roots];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!reachable.add(id)) continue;
      final config = appearance.components[id];
      if (config == null) continue;
      for (final childId in VibeScopeHelpers.childrenOfComponent(config)) {
        if (!reachable.contains(childId)) {
          pending.add(childId);
        }
      }
    }

    return <String>[
      for (final id in appearance.components.keys)
        if (!reachable.contains(id)) id,
    ];
  }

  /// Retourne les identifiants de conteneurs racines [SuperLayoutConfig] candidats
  /// qui ont `0` slot placé dans [appearance].
  static List<String> findEmptyRootLayoutIds(
    Appearance appearance, {
    Iterable<String> mountedComponentIds = const <String>[],
  }) {
    final placedAnywhere = <String>{};
    for (final config in appearance.components.values) {
      placedAnywhere.addAll(VibeScopeHelpers.childrenOfComponent(config));
    }

    final candidates = <String>{
      if (appearance.components.containsKey('mainLayout')) 'mainLayout',
      ...mountedComponentIds,
    };

    final emptyRoots = <String>[];
    for (final id in candidates) {
      final config = appearance.components[id];
      if (config is! SuperLayoutConfig) continue;
      if (config.placedSlotIds.isNotEmpty) continue;
      final isRoot = id == 'mainLayout' || !placedAnywhere.contains(id);
      if (isRoot) {
        emptyRoots.add(id);
      }
    }
    return emptyRoots;
  }

  /// Formate un message de diagnostic explicite et actionnable pour `debugEntries` et l'audit.
  static String formatEmptyRootWarning({
    required String rootLayoutId,
    required List<String> ghostComponentIds,
    int maxSample = 8,
  }) {
    final sample = ghostComponentIds.take(maxSample).join(', ');
    final extra = ghostComponentIds.length > maxSample
        ? ', … (+${ghostComponentIds.length - maxSample})'
        : '';
    return '[LAYOUT DIAGNOSTIC] Le conteneur racine "$rootLayoutId" est monté '
        'avec 0 slot placé alors que ${ghostComponentIds.length} composant(s) '
        'configuré(s) sont fantômes / non rattachés ($sample$extra). '
        'Vérifiez components["$rootLayoutId"].placements.';
  }
}
