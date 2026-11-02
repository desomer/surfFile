/// Configuration persistante de l'editeur SuperCode et codec JSON extensible.
library;

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

/// Langages proposes par SuperCode (coloration uniquement, sans execution).
enum SuperCodeMode {
  yaml('YAML'),
  javascript('JavaScript');

  const SuperCodeMode(this.label);

  /// Libelle du langage dans les formulaires.
  final String label;
}

/// Enregistre le codec et les alias du composant Code.
void ensureSuperCodeCodecsRegistered() {
  if (ComponentConfigCatalog.of('code') == null) {
    ComponentConfigCatalog.register<SuperCodeConfig>(
      const ComponentConfigCodec(
        type: 'code',
        fromJson: SuperCodeConfig.fromJson,
      ),
    );
  }
  JsonComponentType.registerAliases(const {
    'Code': 'Code',
    'SuperCode': 'Code',
    'superCode': 'Code',
  });
}

/// Reglages immuables; le texte saisi reste dans le repository, pas l'apparence.
@immutable
class SuperCodeConfig extends ComponentConfig {
  const SuperCodeConfig({
    this.mode = SuperCodeMode.yaml,
    this.binding,
    this.errorBinding,
    this.readOnly = false,
  });

  /// Langage de coloration syntaxique.
  final SuperCodeMode mode;

  /// Attribut texte du repository, avec heritage et jokers [?].
  final JsonTextBinding? binding;

  /// Attribut du repository affiche en lecture comme message d'erreur.
  final JsonTextBinding? errorBinding;

  /// Interdit les modifications du texte.
  final bool readOnly;

  @override
  String get componentType => 'code';

  @override
  Iterable<JsonTextBinding> get referencedBindings => [?binding, ?errorBinding];

  @override
  void validate() {
    binding?.validate();
    errorBinding?.validate();
  }

  @override
  SuperCodeConfig patchFromJson(Map<Object?, Object?> patch) {
    final json = toJson();
    for (final entry in patch.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('Cle de configuration SuperCode invalide.');
      }
      json[key] = entry.value;
    }
    return SuperCodeConfig.fromJson(json);
  }

  /// Retourne une copie des reglages.
  SuperCodeConfig copyWith({
    SuperCodeMode? mode,
    JsonTextBinding? binding,
    bool clearBinding = false,
    JsonTextBinding? errorBinding,
    bool clearErrorBinding = false,
    bool? readOnly,
  }) => SuperCodeConfig(
    mode: mode ?? this.mode,
    binding: clearBinding ? null : binding ?? this.binding,
    errorBinding: clearErrorBinding ? null : errorBinding ?? this.errorBinding,
    readOnly: readOnly ?? this.readOnly,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'mode': mode.name,
      if (binding != null) 'binding': binding!.toJson(),
      if (errorBinding != null) 'errorBinding': errorBinding!.toJson(),
      'readOnly': readOnly,
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (mode != SuperCodeMode.yaml) 'mode': mode.name,
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (errorBinding != null) 'errorBinding': errorBinding!.toCompactJson(),
      if (readOnly) 'readOnly': true,
    };
  }

  /// Decode et valide les reglages JSON, sans accepter de langage inconnu.
  factory SuperCodeConfig.fromJson(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (!const {'mode', 'binding', 'errorBinding', 'readOnly'}.contains(key)) {
        throw FormatException('Propriete SuperCode inconnue : $key.');
      }
    }
    final rawMode = json['mode'] ?? 'yaml';
    final mode = SuperCodeMode.values.where((item) => item.name == rawMode).firstOrNull;
    if (mode == null) {
      throw const FormatException('Mode SuperCode invalide : yaml ou javascript attendu.');
    }
    final readOnly = json['readOnly'] ?? false;
    if (readOnly is! bool) {
      throw const FormatException('Lecture seule doit etre un booleen.');
    }
    final result = SuperCodeConfig(
      mode: mode,
      binding: json['binding'] == null ? null : JsonTextBinding.fromJson(json['binding']),
      errorBinding: json['errorBinding'] == null
          ? null
          : JsonTextBinding.fromJson(json['errorBinding']),
      readOnly: readOnly,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperCodeConfig &&
      mode == other.mode &&
      binding == other.binding &&
      errorBinding == other.errorBinding &&
      readOnly == other.readOnly;

  @override
  int get hashCode => Object.hash(mode, binding, errorBinding, readOnly);
}
