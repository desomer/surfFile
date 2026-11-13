/// Precision commune aux champs numeriques et aux documents JSON de configuration.
library;

/// Arrondit les nombres sans modifier les textes ni les collections sources.
abstract final class JsonNumbers {
  /// Retourne une valeur finie avec au maximum deux decimales.
  static double round(double value) {
    if (!value.isFinite) {
      throw const FormatException('La valeur doit etre un nombre fini.');
    }
    final rounded = double.parse(value.toStringAsFixed(2));
    return rounded == 0 ? 0 : rounded;
  }

  /// Copie recursivement un document JSON en preservant ses entiers.
  static Object? normalize(Object? value) => switch (value) {
    int() => value,
    double() => round(value),
    Map() => {
      for (final entry in value.entries)
        (entry.key is String
                ? entry.key as String
                : throw const FormatException('Cle JSON non textuelle.')):
            normalize(entry.value),
    },
    List<Object?>() => value.map(normalize).toList(),
    _ => value,
  };

  /// Normalise une map JSON, y compris les champs ajoutes par les codecs hotes.
  static Map<String, Object?> normalizeMap(Map<String, Object?> value) => {
    for (final entry in value.entries) entry.key: normalize(entry.value),
  };
}
