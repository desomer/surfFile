/// Action de comportement réactive liant l'état d'un composant (`invisible`, `readOnly`, `disabled`) à un booléen d'un repository JSON ([StateBindingAction]).
///
/// Observe une valeur booléenne via [JsonTextBinding] et applique l'état cible
/// ([BehaviorBoundState]) lorsque la valeur résolue correspond à [StateBindingAction.whenValue].
library;

import 'package:material_ui/material_ui.dart';

import '../component_behavior.dart';
import '../json_text_binding.dart';

/// État cible contrôlé par une [StateBindingAction].
enum BehaviorBoundState {
  /// Masque le composant hors mode édition.
  invisible('Invisible', 'Masquer le composant', Icons.visibility_off_outlined),

  /// Passe le composant en lecture seule.
  readOnly(
    'Lecture seule',
    'Empêcher la modification de la valeur',
    Icons.edit_off_outlined,
  ),

  /// Désactive le composant et ses interactions.
  disabled('Inactif', 'Désactiver les interactions', Icons.block_outlined);

  const BehaviorBoundState(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// Change l'état d'un composant ([BehaviorBoundState.invisible],
/// [BehaviorBoundState.readOnly] ou [BehaviorBoundState.disabled]) en fonction
/// d'un booléen lié dans un repository JSON.
@immutable
class StateBindingAction extends BehaviorAction {
  const StateBindingAction({
    required this.state,
    required this.binding,
    this.whenValue = true,
    this.maintainSize = false,
  });

  /// État appliqué lorsque la condition booléenne est vérifiée.
  final BehaviorBoundState state;

  /// Liaison vers l'attribut booléen du repository JSON.
  final JsonTextBinding binding;

  /// Valeur booléenne déclenchant l'état (`true` par défaut, `false` pour inverser).
  final bool whenValue;

  /// Conserve l'encombrement du composant lorsqu'il est [BehaviorBoundState.invisible].
  final bool maintainSize;

  /// Valide la syntaxe de la liaison JSON.
  void validate() {
    binding.validate();
  }

  /// Indique si la valeur brute [raw] active l'état configuré.
  ///
  /// Retourne `false` lorsque [raw] est `null` (attribut absent ou aucune ligne sélectionnée).
  /// Lève une [FormatException] si [raw] n'est ni un booléen ni une chaîne booléenne reconnue.
  bool matchesValue(Object? raw) {
    final resolved = parseBoolValue(raw);
    if (resolved == null) return false;
    return resolved == whenValue;
  }

  /// Convertit une valeur brute de repository en booléen (`null` si absente).
  static bool? parseBoolValue(Object? raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is String) {
      return switch (raw.trim().toLowerCase()) {
        'true' || '1' || 'yes' || 'oui' => true,
        'false' || '0' || 'no' || 'non' => false,
        _ => throw const FormatException(
          'La valeur liée à l’état doit être un booléen (true/false).',
        ),
      };
    }
    throw const FormatException(
      'La valeur liée à l’état doit être un booléen (true/false).',
    );
  }

  @override
  String get type => 'bindState';

  @override
  String get label => 'Changer l’état (${state.label.toLowerCase()})';

  @override
  String get description {
    final condition = whenValue ? 'si vrai' : 'si faux';
    final sizeSuffix =
        state == BehaviorBoundState.invisible && maintainSize
        ? ', espace conservé'
        : '';
    return '${state.label} ← ${binding.path} ($condition$sizeSuffix)';
  }

  @override
  IconData get icon => state.icon;

  /// Sans effet : `ComponentStateBehavior` observe lui-même la valeur liée.
  @override
  Future<void> execute(BuildContext context) async {}

  /// Copie immuable de l'action.
  StateBindingAction copyWith({
    BehaviorBoundState? state,
    JsonTextBinding? binding,
    bool? whenValue,
    bool? maintainSize,
  }) => StateBindingAction(
    state: state ?? this.state,
    binding: binding ?? this.binding,
    whenValue: whenValue ?? this.whenValue,
    maintainSize: maintainSize ?? this.maintainSize,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'type': type,
      'state': state.name,
      'binding': binding.toJson(),
      if (!whenValue) 'whenValue': whenValue,
      if (maintainSize && state == BehaviorBoundState.invisible)
        'maintainSize': maintainSize,
    };
  }

  /// Forme compacte compatible avec les liaisons courtes.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'type': type,
      'state': state.name,
      'binding': binding.toCompactJson(),
      if (!whenValue) 'whenValue': whenValue,
      if (maintainSize && state == BehaviorBoundState.invisible)
        'maintainSize': maintainSize,
    };
  }

  /// Décode et valide une [StateBindingAction] persistée.
  factory StateBindingAction.fromJson(Map<String, dynamic> json) {
    final stateName = json['state'];
    final state = BehaviorBoundState.values
        .where((candidate) => candidate.name == stateName)
        .firstOrNull;
    if (state == null) {
      throw FormatException('État de comportement invalide : $stateName');
    }
    if (json['binding'] == null) {
      throw const FormatException(
        'La liaison du comportement d’état est requise.',
      );
    }
    final whenValue = json['whenValue'];
    if (whenValue != null && whenValue is! bool) {
      throw const FormatException(
        'La condition whenValue doit être un booléen.',
      );
    }
    final maintainSize = json['maintainSize'];
    if (maintainSize != null && maintainSize is! bool) {
      throw const FormatException(
        'L’option maintainSize doit être un booléen.',
      );
    }
    final result = StateBindingAction(
      state: state,
      binding: JsonTextBinding.fromJson(json['binding']),
      whenValue: whenValue as bool? ?? true,
      maintainSize: maintainSize as bool? ?? false,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateBindingAction &&
          other.state == state &&
          other.binding == binding &&
          other.whenValue == whenValue &&
          other.maintainSize == maintainSize;

  @override
  int get hashCode => Object.hash(state, binding, whenValue, maintainSize);
}
