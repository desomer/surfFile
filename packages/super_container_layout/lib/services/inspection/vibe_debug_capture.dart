/// Capture dédupliquée des erreurs d'exécution dans [debugEntries] et suivi par tour IA ([VibeDebugCapture]).
///
/// Permet à [SuperApp], aux composants UI et aux moteurs internes (liaisons JSON,
/// JavaScript, polices, saisies utilisateur) d'alimenter [debugEntries] avec une
/// catégorie ([DebugErrorCategory]) et une sévérité ([DebugSeverity]) sans créer
/// de doublon lors des reconstructions Flutter ni lorsque l'application hôte
/// (comme `super_designer`) branche déjà `FlutterError.onError` sur [saveError].
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../diagnostics/debug_entry.dart';

/// Jeton opaque marquant la position courante dans le tampon circulaire [debugEntries].
@immutable
class VibeDebugMarker {
  const VibeDebugMarker._(this._anchor, this._capturedAt);

  final DebugEntry? _anchor;
  final DateTime _capturedAt;
}

/// Service de capture typée, dédupliquée et filtrée de [debugEntries] pour Vibe IA et l'IHM.
abstract final class VibeDebugCapture {
  static final Expando<bool> _seenDetails = Expando<bool>(
    'VibeDebugCapture.seenFlutterErrorDetails',
  );

  static final Map<(String, String), String> _activeComponentDiagnostics =
      <(String, String), String>{};
  static bool _clearListenerRegistered = false;

  static int _activeRegistrations = 0;
  static FlutterExceptionHandler? _previousOnError;
  static FlutterExceptionHandler? _installedHandler;

  static bool get _isWidgetTestBinding => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  static void _ensureClearListenerRegistered() {
    if (_clearListenerRegistered) return;
    _clearListenerRegistered = true;
    registerDebugEntriesClearListener(resetActiveDiagnostics);
  }

  /// Installe l'écouteur chaîné sur [FlutterError.onError] hors environnement `flutter_test`.
  ///
  /// Compté par référence afin de supporter plusieurs montages successifs de `SuperApp`.
  static void attachAppListener() {
    _ensureClearListenerRegistered();
    if (_isWidgetTestBinding) return;
    _activeRegistrations++;
    if (_activeRegistrations > 1 || _installedHandler != null) return;
    final previous = FlutterError.onError;
    _previousOnError = previous;
    void handler(FlutterErrorDetails details) {
      recordFlutterError(details);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    }

    _installedHandler = handler;
    FlutterError.onError = handler;
  }

  /// Désinstalle l'écouteur chaîné si plus aucune instance de `SuperApp` n'est active
  /// et si [FlutterError.onError] pointe toujours sur le gestionnaire installé.
  static void detachAppListener() {
    if (_activeRegistrations <= 0) return;
    _activeRegistrations--;
    if (_activeRegistrations > 0) return;
    if (identical(FlutterError.onError, _installedHandler)) {
      FlutterError.onError = _previousOnError;
    }
    _installedHandler = null;
    _previousOnError = null;
  }

  /// Enregistre un [FlutterErrorDetails] dans [debugEntries] sans doublon.
  static void recordFlutterError(FlutterErrorDetails details) {
    if (_seenDetails[details] == true) return;
    _seenDetails[details] = true;
    final raw = details.exceptionAsString().trim();
    if (raw.isEmpty) return;
    final contextDesc = details.context?.toDescription().trim();
    final message = (contextDesc != null && contextDesc.isNotEmpty)
        ? '[FLUTTER ERROR] $raw (context: $contextDesc)'
        : '[FLUTTER ERROR] $raw';
    final lower = raw.toLowerCase();
    final isFontError =
        lower.contains('unable to load font') ||
        lower.contains('fontloader') ||
        lower.contains('.ttf') ||
        lower.contains('.otf');
    recordTypedError(
      message: message,
      category: isFontError
          ? DebugErrorCategory.font
          : DebugErrorCategory.rendering,
      severity: isFontError ? DebugSeverity.warning : DebugSeverity.critical,
      stackTrace: details.stack,
      source: 'FlutterError',
      visibleInUi: false,
      dedupCoreText: raw,
    );
  }

  /// Enregistre un message d'erreur dans [debugEntries] en ignorant les doublons immédiats.
  static void recordErrorDeduplicated(
    String message, [
    Object? stackTrace,
    String? dedupCoreText,
    DebugErrorCategory? category,
    DebugSeverity? severity,
    String? componentId,
    String? source,
    bool visibleInUi = false,
  ]) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final inferred = (category == null || severity == null)
        ? inferDebugErrorClassification(trimmed)
        : null;
    recordTypedError(
      message: trimmed,
      category: category ?? inferred!.category,
      severity:
          severity ??
          (category != null ? category.defaultSeverity : inferred!.severity),
      stackTrace: stackTrace,
      componentId: componentId,
      source: source,
      visibleInUi: visibleInUi,
      dedupCoreText: dedupCoreText,
    );
  }

  /// Enregistre un diagnostic typé dans [debugEntries] en dédupliquant les doublons immédiats.
  static void recordTypedError({
    required String message,
    required DebugErrorCategory category,
    DebugSeverity? severity,
    Object? stackTrace,
    String? componentId,
    String? source,
    bool visibleInUi = false,
    String? dedupCoreText,
  }) {
    _ensureClearListenerRegistered();
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final resolvedSeverity = severity ?? category.defaultSeverity;
    final core = (dedupCoreText ?? trimmed).trim();
    final now = DateTime.now();

    for (
      var i = debugEntries.length - 1;
      i >= 0 && i >= debugEntries.length - 8;
      i--
    ) {
      final recent = debugEntries[i];
      if (recent.type != DebugEntryType.error) continue;
      if (now.difference(recent.timestamp).inMilliseconds.abs() > 250) {
        break;
      }
      final sameTarget =
          recent.componentId == componentId ||
          recent.componentId == null ||
          componentId == null;
      if (sameTarget &&
          (recent.message == trimmed ||
              (core.isNotEmpty && recent.message.contains(core)) ||
              trimmed.contains(recent.message))) {
        return;
      }
    }

    saveError(
      trimmed,
      stackTrace,
      severity: resolvedSeverity,
      category: category,
      componentId: componentId,
      source: source,
      visibleInUi: visibleInUi,
    );
  }

  /// Synchronise un diagnostic actif lié à un composant UI sans créer de doublon
  /// lors des reconstructions Flutter successives.
  ///
  /// Lorsque [active] passe à `false` (ou que [message] est vide), la clé
  /// `(componentId, sourceKey)` est libérée afin qu'une réapparition ultérieure
  /// soit de nouveau journalisée.
  static void syncComponentDiagnostic({
    required String componentId,
    required String sourceKey,
    required bool active,
    required DebugErrorCategory category,
    required String? message,
    DebugSeverity? severity,
    String? source,
    bool visibleInUi = true,
  }) {
    _ensureClearListenerRegistered();
    final key = (componentId, sourceKey);
    final trimmed = message?.trim() ?? '';
    if (!active || trimmed.isEmpty) {
      _activeComponentDiagnostics.remove(key);
      return;
    }
    final previous = _activeComponentDiagnostics[key];
    if (previous == trimmed) return;
    _activeComponentDiagnostics[key] = trimmed;
    recordTypedError(
      message: trimmed,
      category: category,
      severity: severity ?? category.defaultSeverity,
      componentId: componentId,
      source: source ?? sourceKey,
      visibleInUi: visibleInUi,
    );
  }

  /// Libère tous les diagnostics actifs suivis pour [componentId] (ex. dans `dispose()`).
  static void clearComponentDiagnostics(String componentId) {
    _activeComponentDiagnostics.removeWhere((key, _) => key.$1 == componentId);
  }

  /// Réinitialise le registre interne des diagnostics actifs par composant.
  static void resetActiveDiagnostics() {
    _activeComponentDiagnostics.clear();
  }

  /// Indique si [entry] doit déclencher automatiquement la passe d'auto-vérification Vibe IA.
  ///
  /// Retourne `true` pour les erreurs de sévérité `critical`, `error` ou `warning`
  /// (dont les problèmes de rendu de police), tout en excluant `userInput`.
  static bool shouldTriggerAutoVerify(DebugEntry entry) =>
      entry.type == DebugEntryType.error &&
      entry.severity.rank >= DebugSeverity.warning.rank &&
      entry.category.triggersAiAutoFix;

  /// Formate une entrée de diagnostic de façon compacte et structurée pour les prompts IA.
  static String formatEntryForAi(DebugEntry entry) {
    final severityTag = entry.severity.name.toUpperCase();
    final categoryTag = entry.category.name;
    final compTag = entry.componentId != null && entry.componentId!.isNotEmpty
        ? '[comp:${entry.componentId}]'
        : '';
    final uiTag = entry.visibleInUi ? '[IHM]' : '';
    return '[$severityTag][$categoryTag]$compTag$uiTag ${entry.message}';
  }

  /// Capture un repère instantané sur la fin actuelle de [debugEntries].
  ///
  /// Fonctionne même lorsque le tampon circulaire atteint [maxDebugEntries].
  static VibeDebugMarker markNow() => VibeDebugMarker._(
    debugEntries.isEmpty ? null : debugEntries.last,
    DateTime.now(),
  );

  /// Retourne les entrées ajoutées à [debugEntries] strictement après [marker].
  static List<DebugEntry> entriesSince(
    VibeDebugMarker marker, {
    DebugEntryType? type,
    DebugSeverity? minSeverity,
    Set<DebugErrorCategory>? categories,
    bool forAutoVerify = false,
    bool excludeVibeInternal = true,
  }) {
    if (debugEntries.isEmpty) return const <DebugEntry>[];
    var startIndex = 0;
    final anchor = marker._anchor;
    if (anchor != null) {
      var foundIndex = -1;
      for (var i = debugEntries.length - 1; i >= 0; i--) {
        if (identical(debugEntries[i], anchor)) {
          foundIndex = i;
          break;
        }
      }
      if (foundIndex >= 0) {
        startIndex = foundIndex + 1;
      } else {
        // L'ancre a été évincée du tampon circulaire : filtre par horodatage.
        startIndex = debugEntries.indexWhere(
          (e) => !e.timestamp.isBefore(marker._capturedAt),
        );
        if (startIndex < 0) return const <DebugEntry>[];
      }
    }

    if (startIndex >= debugEntries.length) return const <DebugEntry>[];
    final slice = <DebugEntry>[];
    for (var i = startIndex; i < debugEntries.length; i++) {
      final entry = debugEntries[i];
      if (type != null && entry.type != type) continue;
      if (minSeverity != null && entry.severity.rank < minSeverity.rank) {
        continue;
      }
      if (categories != null &&
          categories.isNotEmpty &&
          !categories.contains(entry.category)) {
        continue;
      }
      if (forAutoVerify && !shouldTriggerAutoVerify(entry)) {
        continue;
      }
      if (excludeVibeInternal && isVibeInternalMessage(entry.message)) {
        continue;
      }
      slice.add(entry);
    }
    return List<DebugEntry>.unmodifiable(slice);
  }

  /// Indique si [message] est un journal interne émis par l'orchestrateur Vibe IA.
  static bool isVibeInternalMessage(String message) =>
      message.startsWith('[Vibe IA]');

  /// Condense une pile d'appels aux [maxLines] premières lignes pertinentes.
  static String? condenseStackTrace(String? raw, {int maxLines = 8}) {
    if (raw == null || raw.trim().isEmpty || maxLines <= 0) return null;
    final lines = raw
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .take(maxLines)
        .toList();
    return lines.isEmpty ? null : lines.join('\n');
  }
}
