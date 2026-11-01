/// Contrat d'extension ([SuperComponentExtension]) permettant d'enrichir le moteur
/// `super_container_layout` avec des composants modulaires externes.
///
/// Une extension enregistre à la fois son codec JSON ([ComponentConfigCatalog]),
/// ses éventuels alias de syntaxe courte ([JsonComponentType]) et son constructeur
/// de widget ([ComponentBuilder]) dans le [Registry].
library;

import 'registry.dart';

/// Contrat déclaratif d'une extension de composant pour `super_container_layout`.
abstract class SuperComponentExtension {
  const SuperComponentExtension();

  /// Nom canonique du composant dans [Registry.registry] (ex: `'Chart'`).
  String get registryType;

  /// Enregistre les codecs [ComponentConfigCodec] dans [ComponentConfigCatalog]
  /// et les alias de type dans [JsonComponentType].
  void registerCodecs();

  /// Enregistre le composant et ses métadonnées d'édition dans [registry].
  void register(
    Registry registry, {
    List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
  });
}
