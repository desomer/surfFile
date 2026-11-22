/// Contrôleur runtime éphémère ([BehaviorRuntimeStateController]) et portée
/// ([BehaviorRuntimeStateScope]) gérant les surcharges impératives de style,
/// visibilité et état (`disabled`, `readOnly`) déclenchées par les behaviors.
///
/// Toutes les surcharges vivent exclusivement en mémoire (sans jamais muter
/// `Appearance` ni persister sur disque) et sont notifiées de manière granulaire
/// par `componentId` afin de ne reconstruire que les composants ciblés.
library;

import 'package:material_ui/material_ui.dart';

import '../../models/behaviours/behavior_style_patch.dart';

const Object _keep = Object();

/// Surcharge runtime en mémoire appliquée à un composant par les comportements
/// impératifs (`setStyle`, `setVisibility`, `setState`).
@immutable
class BehaviorRuntimeOverride {
  /// Crée une surcharge runtime éphémère.
  const BehaviorRuntimeOverride({
    this.visible,
    this.maintainSize = false,
    this.disabled,
    this.readOnly,
    this.style,
    this.styleDurationMs = 0,
  });

  /// Visibilité forcée (`false` = masqué, `true` = forcé visible, `null` = non surchargé).
  final bool? visible;

  /// Conserve l'encombrement lorsque [visible] vaut `false`.
  final bool maintainSize;

  /// État `disabled` forcé (`true` = inactif, `false` = réactivé, `null` = non surchargé).
  final bool? disabled;

  /// État `readOnly` forcé (`true` = lecture seule, `false` = éditable, `null` = non surchargé).
  final bool? readOnly;

  /// Patch de style visuel actif, ou `null` si aucune surcharge de style.
  final BehaviorStylePatch? style;

  /// Durée d'animation (ms) associée au dernier changement de style.
  final int styleDurationMs;

  /// Indique si aucune surcharge n'est active.
  bool get isEmpty =>
      visible == null &&
      disabled == null &&
      readOnly == null &&
      (style == null || style!.isEmpty);

  /// Copie immuable avec possibilité d'effacer explicitement un champ.
  BehaviorRuntimeOverride copyWith({
    Object? visible = _keep,
    bool? maintainSize,
    Object? disabled = _keep,
    Object? readOnly = _keep,
    Object? style = _keep,
    int? styleDurationMs,
  }) => BehaviorRuntimeOverride(
    visible: identical(visible, _keep) ? this.visible : visible as bool?,
    maintainSize: maintainSize ?? this.maintainSize,
    disabled: identical(disabled, _keep) ? this.disabled : disabled as bool?,
    readOnly: identical(readOnly, _keep) ? this.readOnly : readOnly as bool?,
    style: identical(style, _keep) ? this.style : style as BehaviorStylePatch?,
    styleDurationMs: styleDurationMs ?? this.styleDurationMs,
  );

  /// Fusionne [scoped] par-dessus `this` (les surcharges d'une ligne de liste
  /// priment sur les surcharges globales du même composant).
  BehaviorRuntimeOverride merge(BehaviorRuntimeOverride scoped) {
    final mergedStyle = switch ((style, scoped.style)) {
      (null, final s?) => s,
      (final b?, null) => b,
      (final b?, final s?) => b.merge(s),
      (null, null) => null,
    };
    return BehaviorRuntimeOverride(
      visible: scoped.visible ?? visible,
      maintainSize: scoped.visible != null ? scoped.maintainSize : maintainSize,
      disabled: scoped.disabled ?? disabled,
      readOnly: scoped.readOnly ?? readOnly,
      style: mergedStyle,
      styleDurationMs: scoped.style != null
          ? scoped.styleDurationMs
          : styleDurationMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BehaviorRuntimeOverride &&
          other.visible == visible &&
          other.maintainSize == maintainSize &&
          other.disabled == disabled &&
          other.readOnly == readOnly &&
          other.style == style &&
          other.styleDurationMs == styleDurationMs;

  @override
  int get hashCode => Object.hash(
    visible,
    maintainSize,
    disabled,
    readOnly,
    style,
    styleDurationMs,
  );
}

class _MountedComponentEntry {
  _MountedComponentEntry({
    required this.token,
    required this.componentId,
    required this.scopeKey,
    this.readEffectiveVisible,
    this.readEffectiveDisabled,
    this.readEffectiveReadOnly,
  });

  final Object token;
  final String componentId;
  final String? scopeKey;
  final bool Function()? readEffectiveVisible;
  final bool Function()? readEffectiveDisabled;
  final bool Function()? readEffectiveReadOnly;
}

/// Contrôleur centralisé en mémoire des surcharges runtime déclenchées par
/// `SetStyleAction`, `SetVisibilityAction` et `SetStateAction`.
class BehaviorRuntimeStateController extends ChangeNotifier {
  final Map<String, Map<String?, BehaviorRuntimeOverride>> _overrides =
      <String, Map<String?, BehaviorRuntimeOverride>>{};
  final Map<String, ValueNotifier<int>> _componentSignals =
      <String, ValueNotifier<int>>{};
  final Map<Object, _MountedComponentEntry> _mountedByToken =
      <Object, _MountedComponentEntry>{};
  final Map<String, List<_MountedComponentEntry>> _mountedById =
      <String, List<_MountedComponentEntry>>{};

  /// Retourne un [Listenable] dédié à [componentId] afin que seuls les widgets
  /// de ce composant se reconstruisent lorsqu'une surcharge le concerne.
  Listenable listenableFor(String componentId) =>
      _componentSignals.putIfAbsent(componentId, () => ValueNotifier<int>(0));

  /// Enregistre une instance montée pour la résolution de portée de ligne
  /// (`JsonListScope`) et la lecture d'état courant lors d'un `toggle`.
  void registerMountedInstance({
    required Object token,
    required String componentId,
    String? scopeKey,
    bool Function()? readEffectiveVisible,
    bool Function()? readEffectiveDisabled,
    bool Function()? readEffectiveReadOnly,
  }) {
    final previous = _mountedByToken[token];
    if (previous != null) {
      _removeMounted(previous);
    }
    final entry = _MountedComponentEntry(
      token: token,
      componentId: componentId,
      scopeKey: scopeKey,
      readEffectiveVisible: readEffectiveVisible,
      readEffectiveDisabled: readEffectiveDisabled,
      readEffectiveReadOnly: readEffectiveReadOnly,
    );
    _mountedByToken[token] = entry;
    _mountedById
        .putIfAbsent(componentId, () => <_MountedComponentEntry>[])
        .add(entry);
  }

  /// Désenregistre une instance démontée.
  void unregisterMountedInstance(Object token) {
    final existing = _mountedByToken.remove(token);
    if (existing != null) {
      _removeMounted(existing);
    }
  }

  void _removeMounted(_MountedComponentEntry entry) {
    final entries = _mountedById[entry.componentId];
    if (entries == null) return;
    entries.removeWhere((candidate) => identical(candidate.token, entry.token));
    if (entries.isEmpty) {
      _mountedById.remove(entry.componentId);
    }
  }

  /// Indique si au moins une instance de [componentId] est montée dans [scopeKey].
  bool hasMountedInstance(String componentId, {String? scopeKey}) {
    final entries = _mountedById[componentId];
    if (entries == null || entries.isEmpty) return false;
    return entries.any((entry) => entry.scopeKey == scopeKey);
  }

  /// Résout la clé de portée cible pour une action déclenchée depuis
  /// [sourceScopeKey] :
  /// - si [isSelf] est vrai, conserve exactement [sourceScopeKey] ;
  /// - sinon, privilégie une instance montée dans la même ligne [sourceScopeKey]
  ///   si elle existe, ou cible globalement (`null`).
  String? resolveTargetScopeKey(
    String targetComponentId, {
    required bool isSelf,
    String? sourceScopeKey,
  }) {
    if (isSelf) return sourceScopeKey;
    if (sourceScopeKey != null &&
        hasMountedInstance(targetComponentId, scopeKey: sourceScopeKey)) {
      return sourceScopeKey;
    }
    return null;
  }

  _MountedComponentEntry? _findMounted(String componentId, String? scopeKey) {
    final entries = _mountedById[componentId];
    if (entries == null || entries.isEmpty) return null;
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].scopeKey == scopeKey) return entries[i];
    }
    return null;
  }

  /// Retourne la surcharge effective pour `(componentId, scopeKey)` en fusionnant
  /// la surcharge globale (`null`) puis la surcharge spécifique à la ligne.
  BehaviorRuntimeOverride? overrideFor(
    String componentId, {
    String? scopeKey,
  }) {
    final byScope = _overrides[componentId];
    if (byScope == null || byScope.isEmpty) return null;
    final global = byScope[null];
    if (scopeKey == null) return global;
    final scoped = byScope[scopeKey];
    if (global == null) return scoped;
    if (scoped == null) return global;
    return global.merge(scoped);
  }

  BehaviorRuntimeOverride _rawOverride(String componentId, String? scopeKey) =>
      _overrides[componentId]?[scopeKey] ?? const BehaviorRuntimeOverride();

  void _writeOverride(
    String componentId,
    String? scopeKey,
    BehaviorRuntimeOverride next,
  ) {
    final byScope = _overrides[componentId];
    final previous = byScope?[scopeKey];
    if (next.isEmpty) {
      if (previous == null) return;
      byScope!.remove(scopeKey);
      if (byScope.isEmpty) {
        _overrides.remove(componentId);
      }
    } else {
      if (previous == next) return;
      _overrides.putIfAbsent(
        componentId,
        () => <String?, BehaviorRuntimeOverride>{},
      )[scopeKey] = next;
    }
    _notifyComponent(componentId);
  }

  void _notifyComponent(String componentId) {
    final signal = _componentSignals[componentId];
    if (signal != null) {
      signal.value = signal.value + 1;
    }
    notifyListeners();
  }

  /// Force la visibilité (`true` = affiché, `false` = masqué) sur la cible.
  void setVisibility(
    String componentId, {
    String? scopeKey,
    required bool visible,
    bool maintainSize = false,
  }) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(
      componentId,
      scopeKey,
      current.copyWith(
        visible: visible,
        maintainSize: !visible && maintainSize,
      ),
    );
  }

  /// Bascule la visibilité de la cible en tenant compte de son état effectif courant.
  void toggleVisibility(
    String componentId, {
    String? scopeKey,
    bool maintainSize = false,
  }) {
    final effective = overrideFor(componentId, scopeKey: scopeKey);
    final mounted = _findMounted(componentId, scopeKey);
    final currentlyVisible =
        mounted?.readEffectiveVisible?.call() ?? (effective?.visible ?? true);
    setVisibility(
      componentId,
      scopeKey: scopeKey,
      visible: !currentlyVisible,
      maintainSize: maintainSize,
    );
  }

  /// Supprime la surcharge impérative de visibilité de la cible.
  void resetVisibility(String componentId, {String? scopeKey}) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(
      componentId,
      scopeKey,
      current.copyWith(visible: null, maintainSize: false),
    );
  }

  /// Force l'état `disabled` sur la cible.
  void setDisabled(
    String componentId, {
    String? scopeKey,
    required bool disabled,
  }) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(componentId, scopeKey, current.copyWith(disabled: disabled));
  }

  /// Bascule l'état `disabled` de la cible.
  void toggleDisabled(String componentId, {String? scopeKey}) {
    final effective = overrideFor(componentId, scopeKey: scopeKey);
    final mounted = _findMounted(componentId, scopeKey);
    final currentlyDisabled =
        mounted?.readEffectiveDisabled?.call() ??
        (effective?.disabled ?? false);
    setDisabled(componentId, scopeKey: scopeKey, disabled: !currentlyDisabled);
  }

  /// Supprime la surcharge impérative `disabled` de la cible.
  void resetDisabled(String componentId, {String? scopeKey}) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(componentId, scopeKey, current.copyWith(disabled: null));
  }

  /// Force l'état `readOnly` sur la cible.
  void setReadOnly(
    String componentId, {
    String? scopeKey,
    required bool readOnly,
  }) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(componentId, scopeKey, current.copyWith(readOnly: readOnly));
  }

  /// Bascule l'état `readOnly` de la cible.
  void toggleReadOnly(String componentId, {String? scopeKey}) {
    final effective = overrideFor(componentId, scopeKey: scopeKey);
    final mounted = _findMounted(componentId, scopeKey);
    final currentlyReadOnly =
        mounted?.readEffectiveReadOnly?.call() ??
        (effective?.readOnly ?? false);
    setReadOnly(componentId, scopeKey: scopeKey, readOnly: !currentlyReadOnly);
  }

  /// Supprime la surcharge impérative `readOnly` de la cible.
  void resetReadOnly(String componentId, {String? scopeKey}) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(componentId, scopeKey, current.copyWith(readOnly: null));
  }

  /// Fusionne [patch] sur la surcharge de style courante de la cible.
  void applyStyle(
    String componentId, {
    String? scopeKey,
    required BehaviorStylePatch patch,
    int durationMs = 0,
  }) {
    if (patch.isEmpty) return;
    final current = _rawOverride(componentId, scopeKey);
    final merged = current.style == null ? patch : current.style!.merge(patch);
    _writeOverride(
      componentId,
      scopeKey,
      current.copyWith(style: merged, styleDurationMs: durationMs),
    );
  }

  /// Bascule uniquement les propriétés définies dans [patch] sur la cible.
  void toggleStyle(
    String componentId, {
    String? scopeKey,
    required BehaviorStylePatch patch,
    int durationMs = 0,
  }) {
    if (patch.isEmpty) return;
    final current = _rawOverride(componentId, scopeKey);
    final effective = overrideFor(componentId, scopeKey: scopeKey)?.style;
    if (patch.isAppliedIn(effective)) {
      final remaining = current.style?.subtract(patch);
      _writeOverride(
        componentId,
        scopeKey,
        current.copyWith(
          style: remaining == null || remaining.isEmpty ? null : remaining,
          styleDurationMs: durationMs,
        ),
      );
    } else {
      applyStyle(
        componentId,
        scopeKey: scopeKey,
        patch: patch,
        durationMs: durationMs,
      );
    }
  }

  /// Réinitialise toutes les surcharges de style runtime de la cible.
  void resetStyle(
    String componentId, {
    String? scopeKey,
    int durationMs = 0,
  }) {
    final current = _rawOverride(componentId, scopeKey);
    _writeOverride(
      componentId,
      scopeKey,
      current.copyWith(style: null, styleDurationMs: durationMs),
    );
  }

  /// Efface toutes les surcharges (style, visibilité, états) pour une cible.
  void clearComponent(String componentId, {String? scopeKey}) {
    _writeOverride(componentId, scopeKey, const BehaviorRuntimeOverride());
  }

  /// Efface toutes les surcharges runtime de tous les composants.
  void clearAll() {
    if (_overrides.isEmpty) return;
    final affected = _overrides.keys.toList();
    _overrides.clear();
    for (final id in affected) {
      final signal = _componentSignals[id];
      if (signal != null) {
        signal.value = signal.value + 1;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final signal in _componentSignals.values) {
      signal.dispose();
    }
    _componentSignals.clear();
    _overrides.clear();
    _mountedByToken.clear();
    _mountedById.clear();
    super.dispose();
  }
}

/// Portée héritée exposant [BehaviorRuntimeStateController] à l'arbre de widgets.
class BehaviorRuntimeStateScope extends InheritedWidget {
  /// Crée une portée runtime autour de [child].
  const BehaviorRuntimeStateScope({
    required this.controller,
    required super.child,
    super.key,
  });

  /// Contrôleur runtime éphémère partagé par la fenêtre / application.
  final BehaviorRuntimeStateController controller;

  /// Retourne le contrôleur le plus proche et enregistre une dépendance de reconstruction.
  static BehaviorRuntimeStateController? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BehaviorRuntimeStateScope>()
          ?.controller;

  /// Retourne le contrôleur le plus proche sans enregistrer de dépendance
  /// (adapté aux callbacks d'actions impératives).
  static BehaviorRuntimeStateController? maybeReadOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<BehaviorRuntimeStateScope>()
          ?.controller;

  @override
  bool updateShouldNotify(BehaviorRuntimeStateScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}
