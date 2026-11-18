/// Tampon circulaire en mémoire des journaux et erreurs d'exécution capturés
/// par l'application hôte (`FlutterError.onError`, `runZonedGuarded`, `print`).
library;

import 'package:flutter/foundation.dart' show immutable;

/// Nature d'une entrée enregistrée dans [debugEntries].
enum DebugEntryType {
  /// Message standard émis via `print` ou `debugPrint`.
  log,

  /// Erreur Flutter ou exception Dart non interceptée.
  error,
}

/// Entrée immuable de journal ou d'erreur horodatée conservée dans [debugEntries].
@immutable
class DebugEntry {
  /// Crée une entrée de diagnostic horodatée.
  const DebugEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.stackTrace,
  });

  /// Horodatage de capture de l'entrée.
  final DateTime timestamp;

  /// Catégorie de l'entrée ([DebugEntryType.log] ou [DebugEntryType.error]).
  final DebugEntryType type;

  /// Contenu textuel du message ou de l'erreur.
  final String message;

  /// Pile d'appels associée, lorsqu'elle est disponible.
  final String? stackTrace;

  /// Retourne une copie modifiée de cette entrée.
  DebugEntry copyWith({
    DateTime? timestamp,
    DebugEntryType? type,
    String? message,
    Object? stackTrace = _unset,
  }) => DebugEntry(
    timestamp: timestamp ?? this.timestamp,
    type: type ?? this.type,
    message: message ?? this.message,
    stackTrace: identical(stackTrace, _unset)
        ? this.stackTrace
        : stackTrace as String?,
  );

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DebugEntry &&
          timestamp == other.timestamp &&
          type == other.type &&
          message == other.message &&
          stackTrace == other.stackTrace;

  @override
  int get hashCode => Object.hash(timestamp, type, message, stackTrace);

  @override
  String toString() =>
      'DebugEntry(${timestamp.toIso8601String()}, ${type.name}, $message)';
}

/// Capacité maximale par défaut du tampon circulaire [debugEntries].
const int maxDebugEntries = 1000;

/// Historique en mémoire des derniers journaux et erreurs capturés (plafonné à [maxDebugEntries]).
final List<DebugEntry> debugEntries = <DebugEntry>[];

/// Enregistre une ligne de journal dans [debugEntries] en conservant au plus [maxDebugEntries] entrées.
void saveLog(String line, [String? stack]) {
  final now = DateTime.now();
  debugEntries.add(
    DebugEntry(
      timestamp: now,
      type: DebugEntryType.log,
      message: line,
      stackTrace: stack,
    ),
  );
  if (debugEntries.length > maxDebugEntries) debugEntries.removeAt(0);
}

/// Enregistre une erreur dans [debugEntries] en conservant au plus [maxDebugEntries] entrées.
void saveError(String message, dynamic stack) {
  final now = DateTime.now();
  debugEntries.add(
    DebugEntry(
      timestamp: now,
      type: DebugEntryType.error,
      message: message,
      stackTrace: stack?.toString(),
    ),
  );
  if (debugEntries.length > maxDebugEntries) debugEntries.removeAt(0);
}
