/// Contrat d'une classe de génération de code Dart dédiée à un type de composant.
library;

import 'dart_codegen_context.dart';

/// Contrat d'une classe de génération de code Dart dédiée à un type de composant.
///
/// Chaque composant du [Registry] (ou d'une [SuperComponentExtension]) associe
/// son propre [ComponentDartGenerator] afin de sérialiser son instance, sa
/// configuration, ses comportements et ses slots enfants en code Dart.
abstract class ComponentDartGenerator {
  const ComponentDartGenerator();

  /// Génère l'expression Dart construisant le widget pour l'identifiant [id].
  ///
  /// [indent] indique le niveau d'indentation courant (en nombre d'espaces)
  /// pour les lignes suivantes de l'expression retournée.
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  });
}
