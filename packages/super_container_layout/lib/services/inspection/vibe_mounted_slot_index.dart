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

/// Descripteur immuable d'un onglet individuel au sein d'un `SuperTab` monté.
@immutable
class VibeMountedTabItem {
  /// Construit un descripteur d'onglet monté.
  const VibeMountedTabItem({
    required this.index,
    required this.tabId,
    required this.label,
    required this.contentZone,
  });

  /// Indice 0-based de l'onglet.
  final int index;

  /// Identifiant technique du slot d'onglet (ou `<templateId>[<i>]` en mode dynamique).
  final String tabId;

  /// Libellé lisible de l'onglet.
  final String label;

  /// Identifiant de la zone de contenu associée (`content:<tabId>` ou `content`).
  final String contentZone;

  /// Sérialise cet onglet en JSON pour les outils d'introspection.
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'tabId': tabId,
    'label': label,
    'contentZone': contentZone,
  };
}

/// Instantané immuable de l'état d'un composant `SuperTab` monté.
@immutable
class VibeMountedTabSnapshot {
  /// Construit un instantané d'état d'onglets montés.
  VibeMountedTabSnapshot({
    required this.componentId,
    required this.isDynamic,
    required this.activeIndex,
    required List<VibeMountedTabItem> tabs,
  }) : tabs = List<VibeMountedTabItem>.unmodifiable(tabs);

  /// Identifiant du composant `SuperTab`.
  final String componentId;

  /// Indique si le `SuperTab` fonctionne en mode dynamique lié à un tableau JSON.
  final bool isDynamic;

  /// Indice 0-based de l'onglet actuellement actif.
  final int activeIndex;

  /// Liste ordonnée et immuable des onglets disponibles.
  final List<VibeMountedTabItem> tabs;

  /// Nombre total d'onglets disponibles.
  int get tabCount => tabs.length;

  /// Sérialise cet instantané en JSON pour les outils d'introspection.
  Map<String, Object?> toJson() => <String, Object?>{
    'componentId': componentId,
    'mode': isDynamic ? 'dynamic' : 'static',
    'activeIndex': activeIndex,
    'tabCount': tabCount,
    'tabs': [for (final t in tabs) t.toJson()],
  };
}

/// Entrée enregistrée dans [VibeMountedSlotIndex] pour piloter un `SuperTab` monté en aperçu ou en audit.
@immutable
class VibeMountedTabEntry {
  /// Construit une entrée d'introspection pour un `SuperTab` monté.
  const VibeMountedTabEntry({
    required this.token,
    required this.componentId,
    required this.tabContext,
    required this.readSnapshot,
    required this.selectTab,
    required this.restoreTab,
  });

  /// Jeton unique identifiant le `State` propriétaire.
  final Object token;

  /// Identifiant technique du composant `SuperTab`.
  final String componentId;

  /// Fournisseur paresseux du `BuildContext` du `SuperTab` s'il est encore monté.
  final BuildContext? Function() tabContext;

  /// Lit l'instantané courant des onglets et de l'indice actif.
  final VibeMountedTabSnapshot? Function() readSnapshot;

  /// Bascule immédiatement vers l'onglet [index] (sans animation ni écriture repository).
  final bool Function(int index) selectTab;

  /// Restaure l'indice [initialIndex] et lève toute surcharge temporaire d'inspection.
  final void Function(int initialIndex) restoreTab;
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
  final Map<Object, VibeMountedTabEntry> _tabsByToken =
      <Object, VibeMountedTabEntry>{};
  final Map<String, List<VibeMountedTabEntry>> _tabsByComponentId =
      <String, List<VibeMountedTabEntry>>{};

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

  /// Enregistre ou met à jour une instance montée de `SuperTab`.
  void registerTab(VibeMountedTabEntry entry) {
    final previous = _tabsByToken[entry.token];
    if (previous != null) {
      if (previous.componentId == entry.componentId) {
        _tabsByToken[entry.token] = entry;
        final list = _tabsByComponentId[entry.componentId];
        if (list != null) {
          final idx = list.indexWhere((e) => identical(e.token, entry.token));
          if (idx >= 0) {
            list[idx] = entry;
            return;
          }
        }
      }
      _removeTabFromLookup(previous);
    }
    _tabsByToken[entry.token] = entry;
    _tabsByComponentId
        .putIfAbsent(entry.componentId, () => <VibeMountedTabEntry>[])
        .add(entry);
  }

  /// Supprime l'entrée de `SuperTab` associée au jeton [token].
  void unregisterTab(Object token) {
    final existing = _tabsByToken.remove(token);
    if (existing != null) {
      _removeTabFromLookup(existing);
    }
  }

  void _removeTabFromLookup(VibeMountedTabEntry entry) {
    final byId = _tabsByComponentId[entry.componentId];
    if (byId != null) {
      byId.removeWhere((e) => identical(e.token, entry.token));
      if (byId.isEmpty) {
        _tabsByComponentId.remove(entry.componentId);
      }
    }
  }

  /// Retourne les entrées de `SuperTab` montées pour [componentId].
  List<VibeMountedTabEntry> tabEntriesFor(String componentId) =>
      List<VibeMountedTabEntry>.unmodifiable(
        _tabsByComponentId[componentId] ?? const [],
      );

  /// Retourne toutes les entrées de `SuperTab` actuellement enregistrées.
  List<VibeMountedTabEntry> get allTabEntries =>
      List<VibeMountedTabEntry>.unmodifiable(_tabsByToken.values);

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
    _tabsByToken.clear();
    _tabsByComponentId.clear();
    _appRootKeys.clear();
  }
}
