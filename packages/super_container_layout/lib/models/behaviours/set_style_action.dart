/// Action de comportement impérative modifiant dynamiquement le style visuel
/// d'un composant ou d'une surface en mémoire ([SetStyleAction]).
///
/// Prend en charge trois opérations ([BehaviorStyleOperation.apply],
/// [BehaviorStyleOperation.toggle], [BehaviorStyleOperation.reset]), le ciblage
/// de soi-même ou d'un autre composant (`targetComponentId`), les propriétés
/// visuelles courantes (`BehaviorStylePatch`) ainsi que l'activation d'un état
/// métier nommé (`namedState`), sans jamais muter `Appearance`.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/behaviors/behavior_runtime_state_controller.dart';
import '../../services/behaviors/component_runtime_value_registry.dart';
import '../../services/diagnostics/debug_entry.dart';
import '../../services/inspection/vibe_debug_capture.dart';
import '../../services/repositories/json_list_scope.dart';
import '../component_behavior.dart';
import 'behavior_style_patch.dart';

/// Opération appliquée par une [SetStyleAction] sur le style runtime cible.
enum BehaviorStyleOperation {
  /// Applique (fusionne) les propriétés du patch sur le style runtime.
  apply('Appliquer', 'Appliquer les propriétés de style', Icons.palette_outlined),

  /// Bascule les propriétés du patch (applique si absentes, retire si déjà actives).
  toggle(
    'Basculer',
    'Alterner l’application du style au déclenchement',
    Icons.contrast_outlined,
  ),

  /// Efface toutes les surcharges de style runtime sur la cible.
  reset(
    'Réinitialiser',
    'Restaurer le style d’origine du composant',
    Icons.restart_alt,
  );

  const BehaviorStyleOperation(this.label, this.description, this.icon);

  /// Libellé français affiché dans l'éditeur.
  final String label;

  /// Description courte de l'opération.
  final String description;

  /// Icône Material associée.
  final IconData icon;
}

/// Change dynamiquement le style visuel (couleurs, bordure, rayon, opacité,
/// élévation, typographie, état nommé, etc.) du composant déclencheur ou d'un
/// autre composant (`targetComponentId`) dans l'état runtime éphémère.
@immutable
class SetStyleAction extends BehaviorAction {
  /// Crée une action de changement de style runtime.
  const SetStyleAction({
    this.operation = BehaviorStyleOperation.apply,
    this.style = const BehaviorStylePatch(),
    this.targetComponentId,
    this.durationMs = 0,
  });

  /// Opération à effectuer (`apply`, `toggle` ou `reset`).
  final BehaviorStyleOperation operation;

  /// Patch de style à appliquer ou basculer (ignoré pour `reset`).
  final BehaviorStylePatch style;

  /// Identifiant d'un autre composant cible, ou `null` pour le composant lui-même.
  final String? targetComponentId;

  /// Durée optionnelle de transition en millisecondes (`0` = instantané).
  final int durationMs;

  /// Valide la configuration de l'action.
  void validate() {
    if (targetComponentId != null) {
      final trimmed = targetComponentId!.trim();
      if (trimmed.isEmpty || trimmed != targetComponentId) {
        throw const FormatException(
          'L’identifiant targetComponentId de setStyle ne peut pas être vide ni contenir d’espaces superflus.',
        );
      }
    }
    if (durationMs < 0) {
      throw const FormatException(
        'La durée durationMs de setStyle doit être >= 0.',
      );
    }
    style.validate();
    if (operation != BehaviorStyleOperation.reset && style.isEmpty) {
      throw const FormatException(
        'Le comportement setStyle doit définir au moins une propriété de style ou un état nommé.',
      );
    }
  }

  @override
  String get type => 'setStyle';

  @override
  String get label => switch (operation) {
    BehaviorStyleOperation.apply => 'Changer le style',
    BehaviorStyleOperation.toggle => 'Basculer le style',
    BehaviorStyleOperation.reset => 'Réinitialiser le style',
  };

  @override
  String get description {
    final target = targetComponentId == null
        ? 'ce composant'
        : targetComponentId!;
    if (operation == BehaviorStyleOperation.reset) {
      return 'Réinitialiser le style de $target';
    }
    final verb = operation == BehaviorStyleOperation.toggle
        ? 'Basculer'
        : 'Appliquer';
    return '$verb (${style.describe()}) sur $target';
  }

  @override
  IconData get icon => Icons.palette_outlined;

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
            'BehaviorRuntimeStateScope introuvable lors de l’exécution de setStyle sur "$targetId".',
        category: DebugErrorCategory.system,
        severity: DebugSeverity.warning,
        componentId: targetId,
        source: 'SetStyleAction',
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
    switch (operation) {
      case BehaviorStyleOperation.apply:
        controller.applyStyle(
          targetId,
          scopeKey: scopeKey,
          patch: style,
          durationMs: durationMs,
        );
      case BehaviorStyleOperation.toggle:
        controller.toggleStyle(
          targetId,
          scopeKey: scopeKey,
          patch: style,
          durationMs: durationMs,
        );
      case BehaviorStyleOperation.reset:
        controller.resetStyle(
          targetId,
          scopeKey: scopeKey,
          durationMs: durationMs,
        );
    }
  }

  /// Copie immuable de l'action.
  SetStyleAction copyWith({
    BehaviorStyleOperation? operation,
    BehaviorStylePatch? style,
    String? targetComponentId,
    bool clearTargetComponentId = false,
    int? durationMs,
  }) => SetStyleAction(
    operation: operation ?? this.operation,
    style: style ?? this.style,
    targetComponentId: clearTargetComponentId
        ? null
        : (targetComponentId ?? this.targetComponentId),
    durationMs: durationMs ?? this.durationMs,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'operation': operation.name,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
      if (operation != BehaviorStyleOperation.reset) 'style': style.toJson(),
      if (durationMs > 0) 'durationMs': durationMs,
    };
  }

  /// Sérialisation compacte compatible avec les tokens `theme:*` et hex courts.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      if (operation != BehaviorStyleOperation.apply)
        'operation': operation.name,
      if (targetComponentId != null) 'targetComponentId': targetComponentId,
      if (operation != BehaviorStyleOperation.reset)
        'style': style.toCompactJson(),
      if (durationMs > 0) 'durationMs': durationMs,
    };
  }

  /// Décode et valide une [SetStyleAction] depuis JSON.
  factory SetStyleAction.fromJson(Map<String, dynamic> json) {
    final rawOp = json['operation'];
    BehaviorStyleOperation operation;
    if (rawOp == null) {
      operation = BehaviorStyleOperation.apply;
    } else if (rawOp is String) {
      operation =
          BehaviorStyleOperation.values
              .where((candidate) => candidate.name == rawOp)
              .firstOrNull ??
          (throw FormatException('Opération setStyle invalide : "$rawOp".'));
    } else {
      throw const FormatException(
        'Le champ "operation" de setStyle doit être une chaîne.',
      );
    }

    final rawTarget = json['targetComponentId'];
    if (rawTarget != null && rawTarget is! String) {
      throw const FormatException(
        'Le champ "targetComponentId" de setStyle doit être une chaîne.',
      );
    }
    final rawDuration = json['durationMs'];
    if (rawDuration != null && rawDuration is! num) {
      throw const FormatException(
        'Le champ "durationMs" de setStyle doit être numérique.',
      );
    }

    final style = json['style'] == null
        ? const BehaviorStylePatch()
        : BehaviorStylePatch.fromJson(json['style']);

    final action = SetStyleAction(
      operation: operation,
      style: operation == BehaviorStyleOperation.reset
          ? const BehaviorStylePatch()
          : style,
      targetComponentId: rawTarget as String?,
      durationMs: (rawDuration as num?)?.toInt() ?? 0,
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetStyleAction &&
          other.operation == operation &&
          other.style == style &&
          other.targetComponentId == targetComponentId &&
          other.durationMs == durationMs;

  @override
  int get hashCode =>
      Object.hash(operation, style, targetComponentId, durationMs);
}
