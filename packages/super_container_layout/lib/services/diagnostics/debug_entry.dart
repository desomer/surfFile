/// Tampon circulaire en mémoire des journaux et erreurs d'exécution capturés
/// par l'application hôte (`FlutterError.onError`, `runZonedGuarded`, `print`),
/// les composants UI et les moteurs internes (liaisons JSON, JavaScript, polices, saisies).
library;

import 'package:flutter/foundation.dart'
    show ValueNotifier, VoidCallback, immutable;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;

/// Nature d'une entrée enregistrée dans [debugEntries].
enum DebugEntryType {
  /// Message standard émis via `print` ou `debugPrint`.
  log,

  /// Erreur Flutter, exception Dart ou diagnostic d'anomalie typé.
  error,
}

/// Niveau d'importance (sévérité) d'une entrée enregistrée dans [debugEntries].
enum DebugSeverity {
  /// Information générale ou journal standard.
  info(0, 'Info'),

  /// Avertissement non bloquant (ex. police indisponible, repli PDF, saisie invalide).
  warning(1, 'Avertissement'),

  /// Erreur fonctionnelle ou affichée en rouge dans l'IHM (liaison JSON, repository, rendu).
  error(2, 'Erreur'),

  /// Erreur critique bloquante (crash Flutter/Dart, débordement layout, erreur JavaScript).
  critical(3, 'Critique');

  const DebugSeverity(this.rank, this.label);

  /// Rang numérique croissant (`0` = info, `3` = critique).
  final int rank;

  /// Libellé lisible en français.
  final String label;

  /// Parse une sévérité depuis une chaîne (`info`, `warning`, `error`, `critical`).
  static DebugSeverity? tryParse(String? raw) {
    if (raw == null) return null;
    return switch (raw.trim().toLowerCase()) {
      'info' || 'low' => DebugSeverity.info,
      'warning' || 'warn' || 'medium' => DebugSeverity.warning,
      'error' || 'err' => DebugSeverity.error,
      'critical' || 'crit' || 'high' || 'fatal' => DebugSeverity.critical,
      _ => null,
    };
  }
}

/// Catégorie fonctionnelle d'une entrée enregistrée dans [debugEntries].
enum DebugErrorCategory {
  /// Problème de liaison JSON, chemin invalide, repository, provider ou datasource.
  binding('Liaison / Données', DebugSeverity.error),

  /// Erreur de syntaxe ou d'exécution JavaScript (comportement ou attribut calculé).
  javascript('JavaScript', DebugSeverity.critical),

  /// Problème de rendu ou de disponibilité de police de caractères.
  font('Rendu de police', DebugSeverity.warning),

  /// Erreur de validation ou de saisie utilisateur (runtime ou éditeur).
  userInput('Saisie utilisateur', DebugSeverity.warning),

  /// Erreur de rendu Flutter, mise en page, contraintes ou débordement.
  rendering('Rendu / Layout', DebugSeverity.critical),

  /// Erreur ou journal système / général.
  system('Système', DebugSeverity.error);

  const DebugErrorCategory(this.label, this.defaultSeverity);

  /// Libellé lisible en français.
  final String label;

  /// Sévérité par défaut associée à cette catégorie.
  final DebugSeverity defaultSeverity;

  /// Indique si cette catégorie doit déclencher l'auto-vérification post-rendu Vibe IA.
  bool get triggersAiAutoFix => this != DebugErrorCategory.userInput;

  /// Parse une catégorie depuis une chaîne (`binding`, `javascript`/`js`, `font`, `userInput`, `rendering`, `system`).
  static DebugErrorCategory? tryParse(String? raw) {
    if (raw == null) return null;
    return switch (raw.trim().toLowerCase()) {
      'binding' || 'bindings' || 'data' || 'repository' =>
        DebugErrorCategory.binding,
      'javascript' || 'js' || 'script' => DebugErrorCategory.javascript,
      'font' || 'fonts' || 'police' || 'typography' => DebugErrorCategory.font,
      'userinput' || 'user_input' || 'input' || 'saisie' || 'validation' =>
        DebugErrorCategory.userInput,
      'rendering' || 'render' || 'layout' || 'flutter' =>
        DebugErrorCategory.rendering,
      'system' || 'general' => DebugErrorCategory.system,
      _ => null,
    };
  }
}

/// Entrée immuable de journal ou d'erreur horodatée conservée dans [debugEntries].
@immutable
class DebugEntry {
  /// Crée une entrée de diagnostic horodatée et typée.
  const DebugEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.stackTrace,
    DebugSeverity? severity,
    this.category = DebugErrorCategory.system,
    this.componentId,
    this.source,
    this.visibleInUi = false,
  }) : severity =
           severity ??
           (type == DebugEntryType.error
               ? DebugSeverity.error
               : DebugSeverity.info);

  /// Horodatage de capture de l'entrée.
  final DateTime timestamp;

  /// Catégorie de l'entrée ([DebugEntryType.log] ou [DebugEntryType.error]).
  final DebugEntryType type;

  /// Niveau d'importance de l'entrée.
  final DebugSeverity severity;

  /// Catégorie fonctionnelle de l'erreur ou du journal.
  final DebugErrorCategory category;

  /// Identifiant optionnel du composant UI concerné.
  final String? componentId;

  /// Origine technique optionnelle (ex. `SuperValue.binding`, `RunJavaScriptAction`).
  final String? source;

  /// Indique si l'erreur est également affichée en rouge dans l'IHM.
  final bool visibleInUi;

  /// Contenu textuel du message ou de l'erreur.
  final String message;

  /// Pile d'appels associée, lorsqu'elle est disponible.
  final String? stackTrace;

  /// Retourne une copie modifiée de cette entrée.
  DebugEntry copyWith({
    DateTime? timestamp,
    DebugEntryType? type,
    DebugSeverity? severity,
    DebugErrorCategory? category,
    Object? componentId = _unset,
    Object? source = _unset,
    bool? visibleInUi,
    String? message,
    Object? stackTrace = _unset,
  }) => DebugEntry(
    timestamp: timestamp ?? this.timestamp,
    type: type ?? this.type,
    severity: severity ?? this.severity,
    category: category ?? this.category,
    componentId: identical(componentId, _unset)
        ? this.componentId
        : componentId as String?,
    source: identical(source, _unset) ? this.source : source as String?,
    visibleInUi: visibleInUi ?? this.visibleInUi,
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
          severity == other.severity &&
          category == other.category &&
          componentId == other.componentId &&
          source == other.source &&
          visibleInUi == other.visibleInUi &&
          message == other.message &&
          stackTrace == other.stackTrace;

  @override
  int get hashCode => Object.hash(
    timestamp,
    type,
    severity,
    category,
    componentId,
    source,
    visibleInUi,
    message,
    stackTrace,
  );

  @override
  String toString() =>
      'DebugEntry(${timestamp.toIso8601String()}, ${type.name}, '
      '${severity.name}/${category.name}, $message)';
}

/// Capacité maximale par défaut du tampon circulaire [debugEntries].
const int maxDebugEntries = 1000;

/// Historique en mémoire des derniers journaux et erreurs capturés (plafonné à [maxDebugEntries]).
final List<DebugEntry> debugEntries = <DebugEntry>[];

/// Compteur réactif incrémenté à chaque modification de [debugEntries].
///
/// Les notifications émises pendant la phase de construction Flutter sont
/// automatiquement différées après la frame pour éviter toute erreur
/// `markNeedsBuild() called during build`.
final ValueNotifier<int> debugEntriesRevision = ValueNotifier<int>(0);

bool _revisionNotificationScheduled = false;
final List<VoidCallback> _clearDebugEntriesListeners = <VoidCallback>[];

/// Enregistre un rappel exécuté lors de chaque appel à [clearDebugEntries].
void registerDebugEntriesClearListener(VoidCallback listener) {
  if (!_clearDebugEntriesListeners.contains(listener)) {
    _clearDebugEntriesListeners.add(listener);
  }
}

void _notifyDebugEntriesChanged() {
  // ignore: invalid_use_of_protected_member
  if (!debugEntriesRevision.hasListeners) {
    debugEntriesRevision.value++;
    return;
  }
  var inBuildPhase = false;
  try {
    final phase = SchedulerBinding.instance.schedulerPhase;
    inBuildPhase =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
  } on Error {
    inBuildPhase = false;
  }
  if (!inBuildPhase) {
    debugEntriesRevision.value++;
    return;
  }
  if (_revisionNotificationScheduled) return;
  _revisionNotificationScheduled = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _revisionNotificationScheduled = false;
    debugEntriesRevision.value++;
  });
}

void _appendDebugEntry(DebugEntry entry) {
  debugEntries.add(entry);
  if (debugEntries.length > maxDebugEntries) debugEntries.removeAt(0);
  _notifyDebugEntriesChanged();
}

/// Déduit la catégorie et la sévérité par défaut d'un message d'erreur brut
/// lorsque l'appelant n'a pas précisé ces champs explicitement.
({DebugErrorCategory category, DebugSeverity severity})
inferDebugErrorClassification(String message) {
  final lower = message.toLowerCase();
  if (lower.startsWith('[js error]') ||
      lower.startsWith('[javascript error]') ||
      lower.contains('javascript') ||
      lower.contains('quickjs') ||
      lower.contains('jscalculationexception') ||
      lower.contains('syntaxerror:') ||
      lower.contains('referenceerror:') ||
      lower.contains('typeerror:')) {
    return (
      category: DebugErrorCategory.javascript,
      severity: DebugSeverity.critical,
    );
  }
  if (lower.startsWith('[font error]') ||
      lower.contains('police indisponible') ||
      lower.contains('police liée') ||
      lower.contains('fontfamily') ||
      lower.contains('font ') ||
      lower.contains('.ttf')) {
    return (
      category: DebugErrorCategory.font,
      severity: DebugSeverity.warning,
    );
  }
  if (lower.startsWith('[input error]') ||
      lower.startsWith('[user input]') ||
      lower.contains('saisie invalide') ||
      lower.contains('json invalide')) {
    return (
      category: DebugErrorCategory.userInput,
      severity: DebugSeverity.warning,
    );
  }
  if (lower.startsWith('[binding error]') ||
      lower.startsWith('[repository error]') ||
      lower.contains('repository') ||
      lower.contains('liaison') ||
      lower.contains('datasource') ||
      lower.contains('provider')) {
    return (
      category: DebugErrorCategory.binding,
      severity: DebugSeverity.error,
    );
  }
  if (lower.startsWith('[flutter error]') ||
      lower.contains('renderflex') ||
      lower.contains('overflowed') ||
      lower.contains('renderbox') ||
      lower.contains('boxconstraints')) {
    return (
      category: DebugErrorCategory.rendering,
      severity: DebugSeverity.critical,
    );
  }
  return (
    category: DebugErrorCategory.system,
    severity: DebugSeverity.error,
  );
}

/// Enregistre une ligne de journal dans [debugEntries] en conservant au plus [maxDebugEntries] entrées.
void saveLog(
  String line, [
  String? stack,
  DebugErrorCategory category = DebugErrorCategory.system,
  String? componentId,
  String? source,
]) {
  _appendDebugEntry(
    DebugEntry(
      timestamp: DateTime.now(),
      type: DebugEntryType.log,
      severity: DebugSeverity.info,
      category: category,
      componentId: componentId,
      source: source,
      message: line,
      stackTrace: stack,
    ),
  );
}

/// Enregistre une erreur dans [debugEntries] en conservant au plus [maxDebugEntries] entrées.
///
/// Lorsque [category] ou [severity] sont omis, ils sont automatiquement déduits
/// à partir de [message] via [inferDebugErrorClassification].
void saveError(
  String message,
  dynamic stack, {
  DebugSeverity? severity,
  DebugErrorCategory? category,
  String? componentId,
  String? source,
  bool visibleInUi = false,
}) {
  final inferred = (category == null || severity == null)
      ? inferDebugErrorClassification(message)
      : null;
  final resolvedCategory = category ?? inferred!.category;
  final resolvedSeverity =
      severity ??
      (category != null ? category.defaultSeverity : inferred!.severity);
  _appendDebugEntry(
    DebugEntry(
      timestamp: DateTime.now(),
      type: DebugEntryType.error,
      severity: resolvedSeverity,
      category: resolvedCategory,
      componentId: componentId,
      source: source,
      visibleInUi: visibleInUi,
      message: message,
      stackTrace: stack?.toString(),
    ),
  );
}

/// Enregistre un diagnostic typé (erreur ou avertissement) dans [debugEntries].
void saveDiagnostic({
  required String message,
  required DebugErrorCategory category,
  DebugSeverity? severity,
  Object? stackTrace,
  String? componentId,
  String? source,
  bool visibleInUi = false,
}) {
  saveError(
    message,
    stackTrace,
    severity: severity ?? category.defaultSeverity,
    category: category,
    componentId: componentId,
    source: source,
    visibleInUi: visibleInUi,
  );
}

/// Vide le tampon [debugEntries], réinitialise les écouteurs de diagnostic et notifie l'IHM.
void clearDebugEntries() {
  debugEntries.clear();
  for (final listener in List<VoidCallback>.of(_clearDebugEntriesListeners)) {
    listener();
  }
  _notifyDebugEntriesChanged();
}
