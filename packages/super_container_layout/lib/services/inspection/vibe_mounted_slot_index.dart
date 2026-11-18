/// Index runtime léger des slots montés ([VibeMountedSlotIndex]) pour l'introspection Vibe IA.
///
/// Suit en temps réel les instances de [EditorSlot] actives et la racine de
/// rendu de [SuperApp] afin d'accéder en O(1) à leurs `BuildContext`, `RenderBox`
/// et `RenderRepaintBoundary` sans parcourir tout l'arbre Flutter.
library;

import 'package:material_ui/material_ui.dart';

/// Descripteur d'une instance montée de slot enregistrée dans [VibeMountedSlotIndex].
@immutable
class VibeMountedSlotEntry {
  /// Crée une entrée d'index pour un slot monté.
  const VibeMountedSlotEntry({
    required this.token,
    required this.componentId,
    required this.zoneId,
    required this.label,
    required this.componentType,
    required this.scrollable,
    required this.fixedWidth,
    required this.fixedHeight,
    required this.slotContext,
    required this.contentKey,
  });

  /// Jeton unique identifiant l'instance de `State` propriétaire.
  final Object token;

  /// Identifiant technique du composant (`effectiveComponentId`).
  final String componentId;

  /// Identifiant de zone éventuel lorsque le slot représente une zone de conteneur.
  final String? zoneId;

  /// Libellé lisible du slot.
  final String label;

  /// Type d'événement / composant (`eventComponentType`).
  final String componentType;

  /// Indique si le slot est configuré comme défilable.
  final bool scrollable;

  /// Indique si la largeur du slot est fixée.
  final bool fixedWidth;

  /// Indique si la hauteur du slot est fixée.
  final bool fixedHeight;

  /// Fournisseur paresseux du `BuildContext` du slot s'il est encore monté.
  final BuildContext? Function() slotContext;

  /// Clé globale entourant directement le contenu rendu du slot.
  final GlobalKey contentKey;

  /// Clé composite unique `(componentId, zoneId)` utilisée pour l'indexation.
  String get compositeKey =>
      zoneId == null || zoneId!.isEmpty ? componentId : '$componentId::$zoneId';
}

/// Registre global des slots et de la racine applicative actuellement montés à l'écran.
class VibeMountedSlotIndex {
  VibeMountedSlotIndex._();

  /// Instance singleton partagée dans l'application.
  static final VibeMountedSlotIndex instance = VibeMountedSlotIndex._();

  final Map<Object, VibeMountedSlotEntry> _byToken =
      <Object, VibeMountedSlotEntry>{};
  final Map<String, List<VibeMountedSlotEntry>> _byComponentId =
      <String, List<VibeMountedSlotEntry>>{};
  final Map<String, List<VibeMountedSlotEntry>> _byCompositeKey =
      <String, List<VibeMountedSlotEntry>>{};

  final List<GlobalKey> _appRootKeys = <GlobalKey>[];

  /// Enregistre ou met à jour une instance montée de slot identifiée par [entry.token].
  void register(VibeMountedSlotEntry entry) {
    final previous = _byToken[entry.token];
    if (previous != null) {
      if (previous.componentId == entry.componentId &&
          previous.zoneId == entry.zoneId &&
          previous.label == entry.label &&
          previous.componentType == entry.componentType &&
          previous.scrollable == entry.scrollable &&
          previous.fixedWidth == entry.fixedWidth &&
          previous.fixedHeight == entry.fixedHeight &&
          identical(previous.contentKey, entry.contentKey)) {
        return;
      }
      _removeFromLookup(previous);
    }
    _byToken[entry.token] = entry;
    _byComponentId
        .putIfAbsent(entry.componentId, () => <VibeMountedSlotEntry>[])
        .add(entry);
    _byCompositeKey
        .putIfAbsent(entry.compositeKey, () => <VibeMountedSlotEntry>[])
        .add(entry);
  }

  /// Supprime l'entrée associée au jeton [token] lors du démontage du slot.
  void unregister(Object token) {
    final existing = _byToken.remove(token);
    if (existing != null) {
      _removeFromLookup(existing);
    }
  }

  void _removeFromLookup(VibeMountedSlotEntry entry) {
    final byId = _byComponentId[entry.componentId];
    if (byId != null) {
      byId.removeWhere((e) => identical(e.token, entry.token));
      if (byId.isEmpty) {
        _byComponentId.remove(entry.componentId);
      }
    }
    final byComposite = _byCompositeKey[entry.compositeKey];
    if (byComposite != null) {
      byComposite.removeWhere((e) => identical(e.token, entry.token));
      if (byComposite.isEmpty) {
        _byCompositeKey.remove(entry.compositeKey);
      }
    }
  }

  /// Enregistre une clé globale de `RepaintBoundary` racine d'application (`SuperApp`).
  void registerAppRoot(GlobalKey key) {
    if (!_appRootKeys.contains(key)) {
      _appRootKeys.add(key);
    }
  }

  /// Désenregistre une clé globale racine lors de la destruction de l'application.
  void unregisterAppRoot(GlobalKey key) {
    _appRootKeys.remove(key);
  }

  /// Clé globale de la racine applicative la plus récente encore montée, ou `null`.
  GlobalKey? get activeAppRootKey {
    for (var i = _appRootKeys.length - 1; i >= 0; i--) {
      final key = _appRootKeys[i];
      if (key.currentContext != null) {
        return key;
      }
    }
    return null;
  }

  /// Retourne toutes les entrées actuellement montées pour [componentId],
  /// éventuellement filtrées sur [zoneId].
  List<VibeMountedSlotEntry> entriesFor(String componentId, {String? zoneId}) {
    if (zoneId != null && zoneId.isNotEmpty) {
      return List<VibeMountedSlotEntry>.unmodifiable(
        _byCompositeKey['$componentId::$zoneId'] ?? const [],
      );
    }
    return List<VibeMountedSlotEntry>.unmodifiable(
      _byComponentId[componentId] ?? const [],
    );
  }

  /// Retourne l'ensemble des identifiants de composants actuellement montés.
  Set<String> get mountedComponentIds =>
      Set<String>.unmodifiable(_byComponentId.keys);

  /// Retourne toutes les entrées actuellement enregistrées.
  List<VibeMountedSlotEntry> get allEntries =>
      List<VibeMountedSlotEntry>.unmodifiable(_byToken.values);

  /// Retourne un résumé compact dédupliqué des slots actuellement montés à l'écran
  /// (composants persistés et slots applicatifs codés en dur), plafonné à [limit].
  List<String> mountedSlotSummaries({int limit = 40}) {
    if (_byToken.isEmpty || limit <= 0) return const <String>[];
    final seen = <String>{};
    final summaries = <String>[];
    final ordered = <VibeMountedSlotEntry>[
      for (final entry in _byToken.values)
        if (entry.zoneId == null || entry.zoneId!.isEmpty) entry,
      for (final entry in _byToken.values)
        if (entry.zoneId != null && entry.zoneId!.isNotEmpty) entry,
    ];
    for (final entry in ordered) {
      if (summaries.length >= limit) break;
      final ctx = entry.slotContext();
      if (ctx == null || !ctx.mounted) continue;
      final key = entry.compositeKey;
      if (!seen.add(key)) continue;
      final label = entry.label.trim();
      final hasDistinctLabel =
          label.isNotEmpty &&
          label != entry.componentId &&
          label != 'Editable component';
      summaries.add(hasDistinctLabel ? '$key ($label)' : key);
    }
    return List<String>.unmodifiable(summaries);
  }

  /// Vide l'index (utile uniquement pour isoler des tests).
  void clearForTesting() {
    _byToken.clear();
    _byComponentId.clear();
    _byCompositeKey.clear();
    _appRootKeys.clear();
  }
}
