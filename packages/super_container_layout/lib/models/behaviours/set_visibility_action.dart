/// Action de comportement impérative contrôlant la visibilité d'un composant
/// en mémoire ([SetVisibilityAction]).
///
/// Permet d'afficher (`show`), masquer (`hide`), basculer (`toggle`) ou
/// réinitialiser (`reset`) la visibilité du composant déclencheur ou d'un autre
/// composant (`targetComponentId`), avec conservation optionnelle de l'espace
/// (`maintainSize`), sans jamais muter `Appearance`.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/behaviors/behavior_runtime_state_controller.dart';
import '../../services/behaviors/component_runtime_value_registry.dart';
import '../../services/diagnostics/debug_entry.dart';
import '../../services/inspection/vibe_debug_capture.dart';
import '../../services/repositories/json_list_scope.dart';
import '../component_behavior.dart';

/// Mode d'opération de visibilité pour [SetVisibilityAction].
enum BehaviorVisibilityMode {
  /// Affiche explicitement le composant.
  show('Afficher', 'Rendre le composant visible', Icons.visibility_outlined),

  /// Masque le composant (hors mode édition).
  hide('Masquer', 'Cacher le composant', Icons.visibility_off_outlined),

  /// Bascule entre visible et masqué selon l'état courant.
  toggle(
    'Basculer',
    'Alterner entre visible et masqué',
    Icons.flourescent_outlined,
  ),

  /// Supprime la surcharge impérative et rend la main au comportement par défaut.
  reset(
    'Réinitialiser',
    'Restaurer la visibilité par défaut',
    Icons.restart_alt,
  );

  const BehaviorVisibilityMode(this.label, this.description, this.icon);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Description courte de l'opération.
  final String description;

  /// Icône Material associée.
  final IconData icon;
}

/// Change la visibilité du composant courant ou d'un autre composant
/// (`targetComponentId`) lors d'un événement impératif.
@immutable
class SetVisibilityAction extends BehaviorAction {
  /// Crée une action de contrôle de visibilité runtime.
  const SetVisibilityAction({
    this.mode = BehaviorVisibilityMode.hide,
    this.targetComponentId,
    this.maintainSize = false,
  });

  /// Opération de visibilité (`show`, `hide`, `toggle` ou `reset`).
  final BehaviorVisibilityMode mode;

  /// Identifiant d'un autre composant cible, ou `null` pour le composant lui-même.
  final String? targetComponentId;

  /// Conserve l'encombrement dans la mise en page lorsque le composant est masqué.
  final bool maintainSize;

  /// Valide la configuration de l'action.
  void validate() {
    if (targetComponentId != null) {
      final trimmed = targetComponentId!.trim();
      if (trimmed.isEmpty || trimmed != targetComponentId) {
        throw const FormatException(
          'L’identifiant targetComponentId de setVisibility ne peut pas être vide ni contenir d’espaces superflus.',
        );
      }
    }
  }

  @override
  String get type => 'setVisibility';

  @override
  String get label => switch (mode) {
    BehaviorVisibilityMode.show => 'Afficher le composant',
    BehaviorVisibilityMode.hide => 'Masquer le composant',
    BehaviorVisibilityMode.toggle => 'Basculer la visibilité',
    BehaviorVisibilityMode.reset => 'Réinitialiser la visibilité',
  };

  @override
  String get description {
    final target = targetComponentId == null
        ? 'ce composant'
        : targetComponentId!;
    final sizeSuffix =
        maintainSize &&
            (mode == BehaviorVisibilityMode.hide ||
                mode == BehaviorVisibilityMode.toggle)
        ? ' (espace conservé)'
        : '';
    return '${mode.label} $target$sizeSuffix';
  }

  @override
  IconData get icon => mode.icon;

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
            'BehaviorRuntimeStateScope introuvable lors de l’exécution de setVisibility sur "$targetId".',
        category: DebugErrorCategory.system,
        severity: DebugSeverity.warning,
        componentId: targetId,
        source: 'SetVisibilityAction',
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
    switch (mode) {
      case BehaviorVisibilityMode.show:
        controller.setVisibility(targetId, scopeKey: scopeKey, visible: true);
      case BehaviorVisibilityMode.hide:
        controller.setVisibility(
          targetId,
          scopeKey: scopeKey,
          visible: false,
          maintainSize: maintainSize,
        );
      case BehaviorVisibilityMode.toggle:
        controller.toggleVisibility(
          targetId,
          scopeKey: scopeKey,
          maintainSize: maintainSize,
        );
      case BehaviorVisibilityMode.reset:
        controller.resetVisibility(targetId, scopeKey: scopeKey);
    }
  }

  /// Copie immuable de l'action.
  SetVisibilityAction copyWith({
    BehaviorVisibilityMode? mode,
    String? targetComponentId,
    bool clearTargetComponentId = false,
    bool? maintainSize,
  }) => SetVisibilityAction(
    mode: mode ?? this.mode,
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
    maintainSize: maintainSize ?? this.maintainSize,
  );

  bool get _keepsMaintainSize =>
      maintainSize &&
      (mode == BehaviorVisibilityMode.hide ||
          mode == BehaviorVisibilityMode.toggle);

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'mode': mode.name,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
      if (_keepsMaintainSize) 'maintainSize': true,
    };
  }

  /// Sérialisation compacte.
  Map<String, Object?> toCompactJson() => toJson();

  /// Décode et valide une [SetVisibilityAction] depuis JSON.
  factory SetVisibilityAction.fromJson(Map<String, dynamic> json) {
    final rawMode = json['mode'];
    if (rawMode is! String) {
      throw FormatException(
        'Mode de visibilité invalide dans setVisibility : $rawMode',
      );
    }
    final mode = BehaviorVisibilityMode.values
        .where((candidate) => candidate.name == rawMode)
        .firstOrNull;
    if (mode == null) {
      throw FormatException(
        'Mode de visibilité inconnu dans setVisibility : "$rawMode".',
      );
    }
    final rawTarget = json['targetComponentId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'Le champ "targetComponentId" de setVisibility doit être une chaîne.',
      );
    }
    final rawMaintain = json['maintainSize'];
    if (rawMaintain != null && rawMaintain is! bool) {
      throw const FormatException(
        'Le champ "maintainSize" de setVisibility doit être un booléen.',
      );
    }
    final action = SetVisibilityAction(
      mode: mode,
      targetComponentId: rawTarget as String?,
      maintainSize: rawMaintain as bool? ?? false,
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetVisibilityAction &&
          other.mode == mode &&
          other.targetComponentId == targetComponentId &&
          other.maintainSize == maintainSize;

  @override
  int get hashCode => Object.hash(mode, targetComponentId, maintainSize);
}
