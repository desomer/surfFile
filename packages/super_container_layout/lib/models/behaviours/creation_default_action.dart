/// Action de comportement déclarative définissant la valeur par défaut
/// d'une `SuperValue` lors de la création d'une ligne dans un tableau JSON
/// ([CreationDefaultAction]).
///
/// Attachée sur une `SuperValue` avec le déclencheur [BehaviorTrigger.create],
/// elle est lue automatiquement par [AddArrayItemAction] (et l'ajout de ligne
/// dans les listes/tables) pour pré-remplir le champ lié lors de la création
/// de la nouvelle ligne.
library;

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../component_behavior.dart';
import '../json_text_binding.dart';

/// Définit la valeur par défaut appliquée au champ d'une `SuperValue` lors de
/// la création d'une nouvelle ligne dans le tableau associé.
@immutable
class CreationDefaultAction extends BehaviorAction {
  /// Crée une action déclarative de valeur par défaut à la création.
  const CreationDefaultAction({this.defaultValue, this.binding});

  /// Valeur par défaut écrite dans le champ lors de la création de ligne.
  ///
  /// Peut être une chaîne, un nombre, un booléen, `null`, ou une structure JSON.
  final Object? defaultValue;

  /// Liaison cible optionnelle. Lorsque `null`, la liaison `SuperValueConfig.binding`
  /// du composant porteur est utilisée automatiquement.
  final JsonTextBinding? binding;

  /// Vérifie la validité de la liaison éventuelle.
  void validate() {
    binding?.validate();
  }

  @override
  String get type => 'creationDefault';

  @override
  String get label => 'Valeur par défaut à la création';

  @override
  String get description {
    final valueText = _formatPreview(defaultValue);
    final target = binding?.path;
    return target == null || target.trim().isEmpty
        ? 'Défaut à la création : $valueText'
        : 'Défaut à la création ($target) : $valueText';
  }

  @override
  IconData get icon => Icons.add_box_outlined;

  /// Sans effet direct : consommée au moment de l'ajout d'une ligne dans le tableau.
  @override
  Future<void> execute(BuildContext context) async {}

  /// Retourne une copie modifiée de cette action.
  CreationDefaultAction copyWith({
    Object? defaultValue = _keepValue,
    JsonTextBinding? binding,
    bool clearBinding = false,
  }) => CreationDefaultAction(
    defaultValue: identical(defaultValue, _keepValue)
        ? this.defaultValue
        : defaultValue,
    binding: clearBinding ? null : (binding ?? this.binding),
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'type': type,
      'defaultValue': _cloneJson(defaultValue),
      if (binding != null) 'binding': binding!.toJson(),
    };
  }

  /// Sérialisation compacte pour le JSON GenUI.
  Map<String, Object?> toCompactJson() {
    validate();
    return <String, Object?>{
      'type': type,
      'defaultValue': _cloneJson(defaultValue),
      if (binding != null) 'binding': binding!.toCompactJson(),
    };
  }

  /// Décode une instance depuis une carte JSON.
  factory CreationDefaultAction.fromJson(Map<String, dynamic> json) {
    final rawBinding = json['binding'];
    final binding = rawBinding == null
        ? null
        : JsonTextBinding.fromJson(rawBinding);
    return CreationDefaultAction(
      defaultValue: _cloneJson(json['defaultValue']),
      binding: binding,
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreationDefaultAction &&
          _jsonEquals(other.defaultValue, defaultValue) &&
          other.binding == binding;

  @override
  int get hashCode =>
      Object.hash(_deepHash(defaultValue), binding);

  static String _formatPreview(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is bool || value is num) return '$value';
    try {
      return jsonEncode(value);
    } on JsonUnsupportedObjectError {
      return '$value';
    }
  }
}

const Object _keepValue = Object();

Object? _cloneJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _cloneJson(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(<Object?>[
      for (final item in value) _cloneJson(item),
    ]);
  }
  return value;
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.entries.every(
          (entry) =>
              b.containsKey(entry.key) && _jsonEquals(entry.value, b[entry.key]),
        );
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map((e) => Object.hash(e.key, _deepHash(e.value))),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}
