/// Capture dédupliquée des erreurs d'exécution dans [debugEntries] et suivi par tour IA ([VibeDebugCapture]).
///
/// Permet à [SuperApp] d'alimenter [debugEntries] pour les erreurs Flutter
/// (`RenderFlex overflowed`, violations de contraintes, images) et les erreurs
/// de [JsonRepositoryStore] sans créer de doublon lorsque l'application hôte
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

/// Service de capture sans doublon et de filtrage de [debugEntries] pour Vibe IA.
abstract final class VibeDebugCapture {
  static final Expando<bool> _seenDetails = Expando<bool>(
    'VibeDebugCapture.seenFlutterErrorDetails',
  );

  static int _activeRegistrations = 0;
  static FlutterExceptionHandler? _previousOnError;
  static FlutterExceptionHandler? _installedHandler;

  static bool get _isWidgetTestBinding => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  /// Installe l'écouteur chaîné sur [FlutterError.onError] hors environnement `flutter_test`.
  ///
  /// Compté par référence afin de supporter plusieurs montages successifs de `SuperApp`.
  static void attachAppListener() {
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
    recordErrorDeduplicated(message, details.stack, raw);
  }

  /// Enregistre un message d'erreur dans [debugEntries] en ignorant les doublons immédiats.
  static void recordErrorDeduplicated(
    String message, [
    Object? stackTrace,
    String? dedupCoreText,
  ]) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final core = (dedupCoreText ?? trimmed).trim();
    final now = DateTime.now();

    for (
      var i = debugEntries.length - 1;
      i >= 0 && i >= debugEntries.length - 6;
      i--
    ) {
      final recent = debugEntries[i];
      if (recent.type != DebugEntryType.error) continue;
      if (now.difference(recent.timestamp).inMilliseconds.abs() > 250) {
        break;
      }
      if (recent.message == trimmed ||
          (core.isNotEmpty && recent.message.contains(core)) ||
          trimmed.contains(recent.message)) {
        return;
      }
    }

    saveError(trimmed, stackTrace);
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
