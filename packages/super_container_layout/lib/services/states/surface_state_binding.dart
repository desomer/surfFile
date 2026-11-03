/// Résolution réactive des noms d'états métier depuis un repository JSON.
library;

import '../repositories/json_string_binding.dart';

/// Lecteur de texte spécialisé conservant le contrat des états de surface.
class SurfaceStateBinding extends JsonStringBinding {
  SurfaceStateBinding({
    required super.store,
    required super.binding,
    super.scope,
    super.placeholder,
  }) : super(
         typeError: 'Surface state name must be a string.',
         readError: 'Unable to read the surface state from its repository.',
         missingStoreError: 'Repository service unavailable.',
       );

  /// Nom de l'état métier actuellement résolu.
  String? get stateName => value;

  /// Conserve l'accès mutable historique au nom d'état.
  set stateName(String? next) => value = next;
}
