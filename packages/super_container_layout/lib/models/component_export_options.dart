/// Options de génération Dart associées à une instance de composant.
library;

import 'package:material_ui/material_ui.dart';

/// Options d'export en code Dart configurées pour une instance de composant (« Configure as... »).
@immutable
class ComponentExportOptions {
  const ComponentExportOptions({
    this.componentName = '',
    this.generateComponentOnExport = false,
    this.forceComponentOnExport = false,
  });

  /// Nom (clé de registre) utilisé pour `_registry.registerComponent(...)`.
  final String componentName;

  /// Indique que cette instance doit générer un composant dédié lors de l'export en code Dart.
  final bool generateComponentOnExport;

  /// Indique que ce composant ne doit jamais être décomposé lors de l'export (même si « Décomposer les composants composés » est actif).
  final bool forceComponentOnExport;

  ComponentExportOptions copyWith({
    String? componentName,
    bool? generateComponentOnExport,
    bool? forceComponentOnExport,
  }) => ComponentExportOptions(
    componentName: componentName ?? this.componentName,
    generateComponentOnExport:
        generateComponentOnExport ?? this.generateComponentOnExport,
    forceComponentOnExport:
        forceComponentOnExport ?? this.forceComponentOnExport,
  );

  Map<String, Object?> toJson() => {
    'componentName': componentName,
    'generateComponentOnExport': generateComponentOnExport,
    'forceComponentOnExport': forceComponentOnExport,
  };

  factory ComponentExportOptions.fromJson(Map<String, Object?> json) =>
      ComponentExportOptions(
        componentName: (json['componentName'] as String?) ?? '',
        generateComponentOnExport:
            (json['generateComponentOnExport'] as bool?) ?? false,
        forceComponentOnExport:
            (json['forceComponentOnExport'] as bool?) ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is ComponentExportOptions &&
      other.componentName == componentName &&
      other.generateComponentOnExport == generateComponentOnExport &&
      other.forceComponentOnExport == forceComponentOnExport;

  @override
  int get hashCode => Object.hash(
    componentName,
    generateComponentOnExport,
    forceComponentOnExport,
  );
}
