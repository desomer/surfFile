/// Configuration initiale du renderer d'apparence, sans persistance des editions locales.
library;

import 'dart:convert';

import 'component_config.dart';

/// Document initial et racine facultative d'un SuperRenderer.
class SuperRendererConfig extends ComponentConfig {
  const SuperRendererConfig({
    this.source = '',
    this.rootId,
    this.showImport = true,
  });

  /// Export d'apparence initial ; vide pour afficher l'invitation a importer.
  final String source;

  /// Identifiant de page ou de composant ; null utilise la page d'accueil.
  final String? rootId;

  /// Affiche la commande d'import du document local.
  final bool showImport;

  @override
  String get componentType => 'renderer';

  @override
  void validate() {
    if (rootId != null && rootId!.trim().isEmpty) {
      throw const FormatException('Identifiant racine vide.');
    }
    if (source.trim().isNotEmpty && jsonDecode(source) is! Map) {
      throw const FormatException('Un document JSON d\'apparence est requis.');
    }
  }

  /// Copie la configuration initiale sans modifier le document rendu.
  SuperRendererConfig copyWith({
    String? source,
    String? rootId,
    bool clearRoot = false,
    bool? showImport,
  }) => SuperRendererConfig(
    source: source ?? this.source,
    rootId: clearRoot ? null : rootId ?? this.rootId,
    showImport: showImport ?? this.showImport,
  );

  @override
  Map<String, Object?> toJson() => {
    'source': source,
    if (rootId != null) 'rootId': rootId,
    'showImport': showImport,
  };

  @override
  Map<String, Object?> toCompactJson() => toJson();

  @override
  SuperRendererConfig patchFromJson(Map<Object?, Object?> patch) {
    if (patch.keys.any((key) => key is! String)) {
      throw const FormatException('Cle de configuration invalide.');
    }
    return SuperRendererConfig.fromJson({
      ...toJson(),
      for (final entry in patch.entries) entry.key! as String: entry.value,
    });
  }

  /// Decode strictement les parametres du renderer.
  factory SuperRendererConfig.fromJson(Map<String, Object?> json) {
    if (json.keys.any(
          (key) => !const {'source', 'rootId', 'showImport'}.contains(key),
        ) ||
        (json['source'] != null && json['source'] is! String) ||
        (json['rootId'] != null && json['rootId'] is! String) ||
        (json['showImport'] != null && json['showImport'] is! bool)) {
      throw const FormatException('Configuration du renderer invalide.');
    }
    return SuperRendererConfig(
      source: json['source'] as String? ?? '',
      rootId: json['rootId'] as String?,
      showImport: json['showImport'] as bool? ?? true,
    )..validate();
  }

  @override
  bool operator ==(Object other) =>
      other is SuperRendererConfig &&
      source == other.source &&
      rootId == other.rootId &&
      showImport == other.showImport;

  @override
  int get hashCode => Object.hash(source, rootId, showImport);
}
