/// Répartiteur centralisé ([BehaviorDispatcher]) pour l'exécution runtime des
/// comportements impératifs ([ComponentBehavior]).
///
/// Applique de manière uniforme :
/// - la garde de mode édition ([StyleEditScope]) ;
/// - la garde d'état désactivé / invisible ([ComponentBehaviorStateScope]) sans
///   enregistrer de dépendance d'arbre pendant les callbacks ;
/// - la protection anti-réentrance par `(componentId, event)` ;
/// - la temporisation anti-rebond par comportement ([ComponentBehavior.debounceMs]) ;
/// - l'évaluation optionnelle des validateurs ([BehaviorValidatorEvaluator]) et
///   le repli sur [ComponentBehavior.elseAction].
library;

import 'dart:async' show Timer, unawaited;

import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../../widgets/components/component_state_behavior.dart';
import '../../widgets/editing/slots/editor_slot.dart' show StyleEditScope;
import '../diagnostics/debug_entry.dart';
import '../inspection/vibe_debug_capture.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_scope.dart';
import '../repositories/json_repository_store.dart';
import 'behavior_validator_evaluator.dart';

/// Point d'entrée unique pour déclencher les comportements impératifs d'un composant.
abstract final class BehaviorDispatcher {
  /// Profondeur maximale autorisée pour une paire `(componentId, event)` afin
  /// d'empêcher les boucles infinies (ex. `onChanged` -> script -> `onChanged`).
  static const int maxReentrancyDepth = 8;

  static final Map<String, int> _activeDepth = <String, int>{};
  static final Map<String, Timer> _debounceTimers = <String, Timer>{};

  /// Annule tous les minuteurs de temporisation (`debounceMs`) en attente.
  @visibleForTesting
  static void cancelPendingDebounces() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  /// Indique si [behaviors] contient au moins un comportement impératif activé
  /// associé à [event].
  static bool hasImperativeBehavior(
    List<ComponentBehavior> behaviors,
    BehaviorEvent event,
  ) =>
      event.isImperative &&
      behaviors.any((b) => b.enabled && b.event == event);

  /// Retourne la liste effective des comportements de [componentId] sans
  /// enregistrer de dépendance sur [AppearanceScope].
  static List<ComponentBehavior> behaviorsFor(
    BuildContext context,
    String componentId, {
    List<ComponentBehavior>? override,
  }) {
    if (override != null) return override;
    final appearance = context
        .getInheritedWidgetOfExactType<AppearanceScope>()
        ?.notifier
        ?.value;
    return appearance?.behaviorsFor(componentId) ?? const [];
  }

  /// Exécute les comportements activés correspondant à [event] pour [componentId].
  ///
  /// Retourne `true` si au moins un comportement a été effectivement exécuté
  /// (après validation des gardes et de son [BehaviorValidator] éventuel).
  static Future<bool> dispatch(
    BuildContext context, {
    required String componentId,
    required String componentType,
    required BehaviorEvent event,
    Map<String, Object?> data = const {},
    List<ComponentBehavior>? behaviors,
    bool ignoreEditMode = false,
  }) async {
    if (!context.mounted || !event.isImperative) return false;

    if (!ignoreEditMode &&
        (StyleEditScope.maybeReadOf(context)?.value ?? false)) {
      return false;
    }

    final stateScope = ComponentBehaviorStateScope.maybeReadOf(context);
    if (stateScope != null && (stateScope.disabled || stateScope.invisible)) {
      return false;
    }

    final resolvedBehaviors = behaviorsFor(
      context,
      componentId,
      override: behaviors,
    );
    final matching = [
      for (final behavior in resolvedBehaviors)
        if (behavior.enabled && behavior.event == event) behavior,
    ];
    if (matching.isEmpty) return false;

    final guardKey = '$componentId::${event.name}';
    if (!_canEnterReentrancy(guardKey, componentId: componentId)) {
      return false;
    }

    _activeDepth[guardKey] = (_activeDepth[guardKey] ?? 0) + 1;
    var executed = false;
    try {
      final appearance = context
          .getInheritedWidgetOfExactType<AppearanceScope>()
          ?.notifier
          ?.value;
      final store = context
          .getInheritedWidgetOfExactType<JsonRepositoryScope>()
          ?.store;
      final listScope = context.getInheritedWidgetOfExactType<JsonListScope>();

      final validationContext = BehaviorValidationContext(
        context: context,
        componentId: componentId,
        componentType: componentType,
        event: event,
        executionData: data,
        appearance: appearance,
        repositoryStore: store,
        listScope: listScope,
      );

      for (final behavior in matching) {
        if (!context.mounted) break;
        final delayMs = behavior.debounceMs;
        if (delayMs != null && delayMs > 0) {
          _scheduleDebouncedBehavior(
            context,
            behavior: behavior,
            componentId: componentId,
            componentType: componentType,
            event: event,
            data: data,
            ignoreEditMode: ignoreEditMode,
            delayMs: delayMs,
          );
          continue;
        }

        final targetAction = await _resolveActionForBehavior(
          context,
          behavior: behavior,
          validationContext: validationContext,
        );
        if (targetAction == null || !context.mounted) continue;

        final execData = BehaviorExecutionData(
          componentId: componentId,
          componentType: componentType,
          event: event,
          data: data,
        );
        await _executeAction(
          context,
          targetAction: targetAction,
          componentId: componentId,
          execData: execData,
          store: store,
        );
        executed = true;
      }
    } finally {
      _leaveReentrancy(guardKey);
    }
    return executed;
  }

  static void _scheduleDebouncedBehavior(
    BuildContext context, {
    required ComponentBehavior behavior,
    required String componentId,
    required String componentType,
    required BehaviorEvent event,
    required Map<String, Object?> data,
    required bool ignoreEditMode,
    required int delayMs,
  }) {
    final debounceKey = '$componentId::${behavior.id}::${event.name}';
    _debounceTimers.remove(debounceKey)?.cancel();
    late final Timer timer;
    timer = Timer(Duration(milliseconds: delayMs), () {
      if (identical(_debounceTimers[debounceKey], timer)) {
        _debounceTimers.remove(debounceKey);
      }
      unawaited(
        _runDebouncedBehavior(
          context,
          behavior: behavior,
          componentId: componentId,
          componentType: componentType,
          event: event,
          data: data,
          ignoreEditMode: ignoreEditMode,
        ),
      );
    });
    _debounceTimers[debounceKey] = timer;
  }

  static Future<void> _runDebouncedBehavior(
    BuildContext context, {
    required ComponentBehavior behavior,
    required String componentId,
    required String componentType,
    required BehaviorEvent event,
    required Map<String, Object?> data,
    required bool ignoreEditMode,
  }) async {
    if (!context.mounted || !event.isImperative) return;
    if (!ignoreEditMode &&
        (StyleEditScope.maybeReadOf(context)?.value ?? false)) {
      return;
    }

    final stateScope = ComponentBehaviorStateScope.maybeReadOf(context);
    if (stateScope != null && (stateScope.disabled || stateScope.invisible)) {
      return;
    }

    final guardKey = '$componentId::${event.name}';
    if (!_canEnterReentrancy(guardKey, componentId: componentId)) {
      return;
    }

    _activeDepth[guardKey] = (_activeDepth[guardKey] ?? 0) + 1;
    try {
      final appearance = context
          .getInheritedWidgetOfExactType<AppearanceScope>()
          ?.notifier
          ?.value;
      final store = context
          .getInheritedWidgetOfExactType<JsonRepositoryScope>()
          ?.store;
      final listScope = context.getInheritedWidgetOfExactType<JsonListScope>();

      final validationContext = BehaviorValidationContext(
        context: context,
        componentId: componentId,
        componentType: componentType,
        event: event,
        executionData: data,
        appearance: appearance,
        repositoryStore: store,
        listScope: listScope,
      );

      final targetAction = await _resolveActionForBehavior(
        context,
        behavior: behavior,
        validationContext: validationContext,
      );
      if (targetAction == null || !context.mounted) return;

      final execData = BehaviorExecutionData(
        componentId: componentId,
        componentType: componentType,
        event: event,
        data: data,
      );
      try {
        await _executeAction(
          context,
          targetAction: targetAction,
          componentId: componentId,
          execData: execData,
          store: store,
        );
      } catch (_) {
        // L'erreur a déjà été consignée dans _executeAction ; ne pas propager
        // dans la zone asynchrone du minuteur.
      }
    } finally {
      _leaveReentrancy(guardKey);
    }
  }

  static Future<BehaviorAction?> _resolveActionForBehavior(
    BuildContext context, {
    required ComponentBehavior behavior,
    required BehaviorValidationContext validationContext,
  }) async {
    final validator = behavior.validator;
    if (validator == null) return behavior.action;
    final valid = await BehaviorValidatorEvaluator.evaluate(
      validator,
      validationContext,
    );
    if (!context.mounted) return null;
    return valid ? behavior.action : behavior.elseAction;
  }

  static Future<void> _executeAction(
    BuildContext context, {
    required BehaviorAction targetAction,
    required String componentId,
    required BehaviorExecutionData execData,
    required JsonRepositoryStore? store,
  }) async {
    try {
      await targetAction.executeWithData(context, execData);
    } catch (error, stack) {
      final isJs = targetAction is RunJavaScriptAction;
      final category = isJs
          ? DebugErrorCategory.javascript
          : DebugErrorCategory.system;
      final message = error is FormatException
          ? error.message
          : 'Échec de l’action ${targetAction.type} sur $componentId : $error';
      if (store != null) {
        store.reportBindingError(
          message,
          category: category,
          severity: DebugSeverity.critical,
          componentId: componentId,
          source: 'BehaviorDispatcher.${targetAction.type}',
          stackTrace: stack,
        );
      } else {
        VibeDebugCapture.recordTypedError(
          message: message,
          category: category,
          severity: DebugSeverity.critical,
          stackTrace: stack,
          componentId: componentId,
          source: 'BehaviorDispatcher.${targetAction.type}',
        );
      }
      rethrow;
    }
  }

  static bool _canEnterReentrancy(
    String guardKey, {
    required String componentId,
  }) {
    final depth = _activeDepth[guardKey] ?? 0;
    if (depth >= maxReentrancyDepth) {
      final msg =
          'BehaviorDispatcher: profondeur maximale ($maxReentrancyDepth) atteinte '
          'pour "$guardKey" ; déclenchement ignoré.';
      debugPrint(msg);
      VibeDebugCapture.recordTypedError(
        message: msg,
        category: DebugErrorCategory.system,
        severity: DebugSeverity.warning,
        componentId: componentId,
        source: 'BehaviorDispatcher.reentrancy',
      );
      return false;
    }
    return true;
  }

  static void _leaveReentrancy(String guardKey) {
    final remaining = (_activeDepth[guardKey] ?? 1) - 1;
    if (remaining <= 0) {
      _activeDepth.remove(guardKey);
    } else {
      _activeDepth[guardKey] = remaining;
    }
  }
}
