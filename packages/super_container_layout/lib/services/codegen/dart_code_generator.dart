/// Socle de génération de code Dart ([ComponentDartGenerator], [DartCodegenContext], [DartCodeExporter]).
///
/// Permet à chaque composant enregistré dans le [Registry] de disposer de sa propre
/// classe de génération de code Dart et d'exporter un sous-graphe d'[Appearance]
/// sous la forme d'une déclaration `_registry.registerComponent(...)`.
library;

export 'core/component_dart_generator.dart';
export 'core/dart_codegen_context.dart';
export 'core/dart_code_exporter.dart';
