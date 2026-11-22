/// Action de comportement impérative contrôlant l'état interactif (`disabled`,
/// `readOnly`) d'un composant en mémoire ([SetStateAction]).
///
/// Permet d'activer, désactiver, basculer ou réinitialiser l'état `disabled`
/// ou `readOnly` du composant déclencheur ou d'un autre composant
/// (`targetComponentId`), sans jamais muter `Appearance`.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/behaviors/behavior_runtime_state_controller.dart';
import '../../services/behaviors/component_runtime_value_registry.dart';
import '../../services/diagnostics/debug_entry.dart';
import '../../services/inspection/vibe_debug_capture.dart';
import '../../services/repositories/json_list_scope.dart';
import '../component_behavior.dart';

/// État interactif contrôlé par une [SetStateAction].
enum BehaviorInteractiveState {
  /// Désactive le composant et bloque ses interactions (pointeur, focus, behaviors).
  disabled(
    'Inactif (disabled)',
    'Désactiver ou réactiver les interactions du composant',
    Icons.block_outlined,
  ),

  /// Passe le composant en lecture seule (`readOnly`).
  readOnly(
    'Lecture seule (readOnly)',
    'Empêcher ou autoriser la modification de la valeur',
    Icons.edit_off_outlined,
  );

  const BehaviorInteractiveState(this.label, this.description, this.icon);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Description courte de l'état.
  final String description;

  /// Icône Material associée.
  final IconData icon;
}

/// Opération appliquée sur un [BehaviorInteractiveState] par [SetStateAction].
enum BehaviorStateOperation {
  /// Force l'état à [SetStateAction.value] (`true` ou `false`).
  set('Définir', 'Forcer l’état à vrai ou faux'),

  /// Bascule l'état courant (`true` ↔ `false`).
  toggle('Basculer', 'Inverser l’état courant'),

  /// Supprime la surcharge impérative et rend la main au comportement par défaut.
  reset('Réinitialiser', 'Restaurer l’état par défaut');

  const BehaviorStateOperation(this.label, this.description);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Description courte de l'opération.
  final String description;
}

/// Change l'état interactif (`disabled` ou `readOnly`) du composant courant ou
/// d'un autre composant (`targetComponentId`) lors d'un événement impératif.
@immutable
class SetStateAction extends BehaviorAction {
  /// Crée une action de modification d'état interactif runtime.
  const SetStateAction({
    this.state = BehaviorInteractiveState.disabled,
    this.operation = BehaviorStateOperation.set,
    this.value = true,
    this.targetComponentId,
  });

  /// État interactif ciblé (`disabled` ou `readOnly`).
  final BehaviorInteractiveState state;

  /// Opération appliquée (`set`, `toggle` ou `reset`).
  final BehaviorStateOperation operation;

  /// Valeur appliquée lorsque [operation] vaut [BehaviorStateOperation.set]
  /// (`true` = activer `disabled`/`readOnly`, `false` = réactiver/autoriser).
  final bool value;

  /// Identifiant d'un autre composant cible, ou `null` pour le composant lui-même.
  final String? targetComponentId;

  /// Valide la configuration de l'action.
  void validate() {
    if (targetComponentId != null) {
      final trimmed = targetComponentId!.trim();
      if (trimmed.isEmpty || trimmed != targetComponentId) {
        throw const FormatException(
          'L’identifiant targetComponentId de setState ne peut pas être vide ni contenir d’espaces superflus.',
        );
      }
    }
  }

  @override
  String get type => 'setState';

  @override
  String get label => switch ((state, operation, value)) {
    (BehaviorInteractiveState.disabled, BehaviorStateOperation.set, true) =>
      'Désactiver le composant',
    (BehaviorInteractiveState.disabled, BehaviorStateOperation.set, false) =>
      'Réactiver le composant',
    (BehaviorInteractiveState.disabled, BehaviorStateOperation.toggle, _) =>
      'Basculer l’état inactif',
    (BehaviorInteractiveState.disabled, BehaviorStateOperation.reset, _) =>
      'Réinitialiser l’état inactif',
    (BehaviorInteractiveState.readOnly, BehaviorStateOperation.set, true) =>
      'Passer en lecture seule',
    (BehaviorInteractiveState.readOnly, BehaviorStateOperation.set, false) =>
      'Autoriser la modification',
    (BehaviorInteractiveState.readOnly, BehaviorStateOperation.toggle, _) =>
      'Basculer la lecture seule',
    (BehaviorInteractiveState.readOnly, BehaviorStateOperation.reset, _) =>
      'Réinitialiser la lecture seule',
  };

  @override
  String get description {
    final target = targetComponentId == null
        ? 'ce composant'
        : targetComponentId!;
    return '$label ($target)';
  }

  @override
  IconData get icon => switch ((state, operation, value)) {
    (BehaviorInteractiveState.disabled, BehaviorStateOperation.set, false) =>
      Icons.check_circle_outline,
    (BehaviorInteractiveState.readOnly, BehaviorStateOperation.set, false) =>
      Icons.edit_outlined,
    (_, BehaviorStateOperation.reset, _) => Icons.restart_alt,
    _ => state.icon,
  };

  @override
  Set<String> get referencedComponentIds =>
      targetComponentId == null ? const {} : {targetComponentId!};

  @override
  BehaviorAction remapComponentIds(Map<String, String> idMap) {
    final target = targetComponentId;
    if (target == null) return this;
    final remapped = idMap[target];
    if (remapped == null || remapped == target) return this;
    return copyWith(targetComponentId: remapped);
  }

  @override
  Future<void> execute(BuildContext context) async {
    validate();
    final targetId = targetComponentId;
    if (targetId == null) return;
    _applyOnTarget(context, targetId: targetId, isSelf: false);
  }

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) async {
    validate();
    final isSelf = targetComponentId == null;
    final targetId = targetComponentId ?? data.componentId;
    _applyOnTarget(context, targetId: targetId, isSelf: isSelf);
  }

  void _applyOnTarget(
    BuildContext context, {
    required String targetId,
    required bool isSelf,
  }) {
    final controller = BehaviorRuntimeStateScope.maybeReadOf(context);
    if (controller == null) {
      VibeDebugCapture.recordTypedError(
        message:
            'BehaviorRuntimeStateScope introuvable lors de l’exécution de setState sur "$targetId".',
        category: DebugErrorCategory.system,
        severity: DebugSeverity.warning,
        componentId: targetId,
        source: 'SetStateAction',
      );
      return;
    }
    final sourceScopeKey = ComponentRuntimeValueRegistry.scopeKeyOf(
      context.getInheritedWidgetOfExactType<JsonListScope>(),
    );
    final scopeKey = controller.resolveTargetScopeKey(
      targetId,
      isSelf: isSelf,
      sourceScopeKey: sourceScopeKey,
    );
    switch ((state, operation)) {
      case (BehaviorInteractiveState.disabled, BehaviorStateOperation.set):
        controller.setDisabled(targetId, scopeKey: scopeKey, disabled: value);
      case (BehaviorInteractiveState.disabled, BehaviorStateOperation.toggle):
        controller.toggleDisabled(targetId, scopeKey: scopeKey);
      case (BehaviorInteractiveState.disabled, BehaviorStateOperation.reset):
        controller.resetDisabled(targetId, scopeKey: scopeKey);
      case (BehaviorInteractiveState.readOnly, BehaviorStateOperation.set):
        controller.setReadOnly(targetId, scopeKey: scopeKey, readOnly: value);
      case (BehaviorInteractiveState.readOnly, BehaviorStateOperation.toggle):
        controller.toggleReadOnly(targetId, scopeKey: scopeKey);
      case (BehaviorInteractiveState.readOnly, BehaviorStateOperation.reset):
        controller.resetReadOnly(targetId, scopeKey: scopeKey);
    }
  }

  /// Copie immuable de l'action.
  SetStateAction copyWith({
    BehaviorInteractiveState? state,
    BehaviorStateOperation? operation,
    bool? value,
    String? targetComponentId,
    bool clearTargetComponentId = false,
  }) => SetStateAction(
    state: state ?? this.state,
    operation: operation ?? this.operation,
    value: value ?? this.value,
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'state': state.name,
      'operation': operation.name,
      if (operation == BehaviorStateOperation.set) 'value': value,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
    };
  }

  /// Sérialisation compacte.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      'state': state.name,
      if (operation != BehaviorStateOperation.set) 'operation': operation.name,
      if (operation == BehaviorStateOperation.set && !value) 'value': false,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
    };
  }

  /// Décode et valide une [SetStateAction] depuis JSON.
  factory SetStateAction.fromJson(Map<String, dynamic> json) {
    final rawState = json['state'];
    if (rawState is! String) {
      throw FormatException('État invalide dans setState : $rawState');
    }
    final state = BehaviorInteractiveState.values
        .where((candidate) => candidate.name == rawState)
        .firstOrNull;
    if (state == null) {
      throw FormatException('État inconnu dans setState : "$rawState".');
    }

    final rawOp = json['operation'];
    BehaviorStateOperation operation;
    if (rawOp == null) {
      operation = BehaviorStateOperation.set;
    } else if (rawOp is String) {
      operation =
          BehaviorStateOperation.values
              .where((candidate) => candidate.name == rawOp)
              .firstOrNull ??
          (throw FormatException('Opération setState invalide : "$rawOp".'));
    } else {
      throw const FormatException(
        'Le champ "operation" de setState doit être une chaîne.',
      );
    }

    final rawValue = json['value'];
    if (rawValue != null && rawValue is! bool) {
      throw const FormatException(
        'Le champ "value" de setState doit être un booléen.',
      );
    }
    final rawTarget = json['targetComponentId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'Le champ "targetComponentId" de setState doit être une chaîne.',
      );
    }

    final action = SetStateAction(
      state: state,
      operation: operation,
      value: rawValue as bool? ?? true,
      targetComponentId: rawTarget as String?,
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetStateAction &&
          other.state == state &&
          other.operation == operation &&
          other.value == value &&
          other.targetComponentId == targetComponentId;

  @override
  int get hashCode => Object.hash(state, operation, value, targetComponentId);
}
