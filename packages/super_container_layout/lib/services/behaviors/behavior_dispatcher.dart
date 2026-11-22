/// Répartiteur centralisé ([BehaviorDispatcher]) pour l'exécution runtime des
/// comportements impératifs ([ComponentBehavior]).
///
/// Applique de manière uniforme :
/// - la garde de mode édition ([StyleEditScope]) ;
/// - la garde d'état désactivé / invisible ([ComponentBehaviorStateScope]) sans
///   enregistrer de dépendance d'arbre pendant les callbacks ;
/// - la protection anti-réentrance par `(componentId, event)` ;
/// - l'évaluation optionnelle des validateurs ([BehaviorValidatorEvaluator]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/component_behavior.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../../widgets/components/component_state_behavior.dart';
import '../../widgets/editing/slots/editor_slot.dart' show StyleEditScope;
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_scope.dart';
import 'behavior_validator_evaluator.dart';

/// Point d'entrée unique pour déclencher les comportements impératifs d'un composant.
abstract final class BehaviorDispatcher {
  /// Profondeur maximale autorisée pour une paire `(componentId, event)` afin
  /// d'empêcher les boucles infinies (ex. `onChanged` -> script -> `onChanged`).
  static const int maxReentrancyDepth = 8;

  static final Map<String, int> _activeDepth = <String, int>{};

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
    final depth = _activeDepth[guardKey] ?? 0;
    if (depth >= maxReentrancyDepth) {
      debugPrint(
        'BehaviorDispatcher: profondeur maximale ($maxReentrancyDepth) atteinte '
        'pour "$guardKey" ; déclenchement ignoré.',
      );
      return false;
    }

    _activeDepth[guardKey] = depth + 1;
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
        final validator = behavior.validator;
        if (validator != null) {
          final valid = await BehaviorValidatorEvaluator.evaluate(
            validator,
            validationContext,
          );
          if (!valid || !context.mounted) continue;
        }
        final execData = BehaviorExecutionData(
          componentId: componentId,
          componentType: componentType,
          event: event,
          data: data,
        );
        await behavior.action.executeWithData(context, execData);
        executed = true;
      }
    } finally {
      final remaining = (_activeDepth[guardKey] ?? 1) - 1;
      if (remaining <= 0) {
        _activeDepth.remove(guardKey);
      } else {
        _activeDepth[guardKey] = remaining;
      }
    }
    return executed;
  }
}
