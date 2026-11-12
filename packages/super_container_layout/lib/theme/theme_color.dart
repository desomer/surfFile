/// Références immuables aux rôles Material 3, conservées dans les configurations
/// et résolues avec le ColorScheme local uniquement au moment du rendu.
library;

import 'package:material_ui/material_ui.dart';

/// Rôle sémantique de couleur fourni par le thème Material 3.
enum ThemeColorRole {
  primary('Marque', 'Couleur principale de la marque'),
  onPrimary('Marque', 'Texte et icônes sur primary'),
  primaryContainer('Marque', 'Variante douce de primary'),
  onPrimaryContainer('Marque', 'Texte et icônes sur primaryContainer'),
  secondary('Marque', 'Couleur secondaire'),
  onSecondary('Marque', 'Texte et icônes sur secondary'),
  secondaryContainer('Marque', 'Variante douce de secondary'),
  onSecondaryContainer('Marque', 'Texte et icônes sur secondaryContainer'),
  tertiary('Marque', 'Couleur complémentaire'),
  onTertiary('Marque', 'Texte et icônes sur tertiary'),
  tertiaryContainer('Marque', 'Variante douce de tertiary'),
  onTertiaryContainer('Marque', 'Texte et icônes sur tertiaryContainer'),
  surface('Surfaces', 'Fond général de l’application'),
  onSurface('Surfaces', 'Texte et icônes sur les surfaces'),
  onSurfaceVariant('Surfaces', 'Texte et icônes secondaires'),
  surfaceDim('Surfaces', 'Surface atténuée'),
  surfaceBright('Surfaces', 'Surface lumineuse'),
  surfaceContainerLowest('Surfaces', 'Niveau de conteneur le plus bas'),
  surfaceContainerLow('Surfaces', 'Niveau de conteneur bas'),
  surfaceContainer('Surfaces', 'Niveau de conteneur standard'),
  surfaceContainerHigh('Surfaces', 'Niveau de conteneur élevé'),
  surfaceContainerHighest('Surfaces', 'Niveau de conteneur le plus élevé'),
  outline('Contours', 'Bordures et séparateurs'),
  outlineVariant('Contours', 'Bordures discrètes'),
  inverseSurface('Inversées', 'Fond inversé, notamment les SnackBar'),
  onInverseSurface('Inversées', 'Texte et icônes sur inverseSurface'),
  inversePrimary('Inversées', 'Accent sur une surface inversée'),
  error('Erreur', 'Couleur d’erreur'),
  onError('Erreur', 'Texte et icônes sur error'),
  errorContainer('Erreur', 'Fond doux d’erreur'),
  onErrorContainer('Erreur', 'Texte et icônes sur errorContainer'),
  shadow('Effets', 'Ombres portées'),
  scrim('Effets', 'Voile des fenêtres modales'),
  surfaceTint('Effets', 'Teinte des surfaces'),
  primaryFixed('Fixes', 'Primary constant entre thèmes clair et sombre'),
  primaryFixedDim('Fixes', 'Primary fixe atténué'),
  onPrimaryFixed('Fixes', 'Texte sur primaryFixed'),
  onPrimaryFixedVariant('Fixes', 'Texte secondaire sur primaryFixed'),
  secondaryFixed('Fixes', 'Secondary constant entre thèmes clair et sombre'),
  secondaryFixedDim('Fixes', 'Secondary fixe atténué'),
  onSecondaryFixed('Fixes', 'Texte sur secondaryFixed'),
  onSecondaryFixedVariant('Fixes', 'Texte secondaire sur secondaryFixed'),
  tertiaryFixed('Fixes', 'Tertiary constant entre thèmes clair et sombre'),
  tertiaryFixedDim('Fixes', 'Tertiary fixe atténué'),
  onTertiaryFixed('Fixes', 'Texte sur tertiaryFixed'),
  onTertiaryFixedVariant('Fixes', 'Texte secondaire sur tertiaryFixed');

  const ThemeColorRole(this.group, this.description);

  /// Famille présentée dans le sélecteur.
  final String group;

  /// Description du rôle sémantique.
  final String description;

  /// Lit la couleur de ce rôle dans le thème courant.
  Color resolve(ColorScheme scheme) => switch (this) {
    primary => scheme.primary,
    onPrimary => scheme.onPrimary,
    primaryContainer => scheme.primaryContainer,
    onPrimaryContainer => scheme.onPrimaryContainer,
    secondary => scheme.secondary,
    onSecondary => scheme.onSecondary,
    secondaryContainer => scheme.secondaryContainer,
    onSecondaryContainer => scheme.onSecondaryContainer,
    tertiary => scheme.tertiary,
    onTertiary => scheme.onTertiary,
    tertiaryContainer => scheme.tertiaryContainer,
    onTertiaryContainer => scheme.onTertiaryContainer,
    surface => scheme.surface,
    onSurface => scheme.onSurface,
    onSurfaceVariant => scheme.onSurfaceVariant,
    surfaceDim => scheme.surfaceDim,
    surfaceBright => scheme.surfaceBright,
    surfaceContainerLowest => scheme.surfaceContainerLowest,
    surfaceContainerLow => scheme.surfaceContainerLow,
    surfaceContainer => scheme.surfaceContainer,
    surfaceContainerHigh => scheme.surfaceContainerHigh,
    surfaceContainerHighest => scheme.surfaceContainerHighest,
    outline => scheme.outline,
    outlineVariant => scheme.outlineVariant,
    inverseSurface => scheme.inverseSurface,
    onInverseSurface => scheme.onInverseSurface,
    inversePrimary => scheme.inversePrimary,
    error => scheme.error,
    onError => scheme.onError,
    errorContainer => scheme.errorContainer,
    onErrorContainer => scheme.onErrorContainer,
    shadow => scheme.shadow,
    scrim => scheme.scrim,
    surfaceTint => scheme.surfaceTint,
    primaryFixed => scheme.primaryFixed,
    primaryFixedDim => scheme.primaryFixedDim,
    onPrimaryFixed => scheme.onPrimaryFixed,
    onPrimaryFixedVariant => scheme.onPrimaryFixedVariant,
    secondaryFixed => scheme.secondaryFixed,
    secondaryFixedDim => scheme.secondaryFixedDim,
    onSecondaryFixed => scheme.onSecondaryFixed,
    onSecondaryFixedVariant => scheme.onSecondaryFixedVariant,
    tertiaryFixed => scheme.tertiaryFixed,
    tertiaryFixedDim => scheme.tertiaryFixedDim,
    onTertiaryFixed => scheme.onTertiaryFixed,
    onTertiaryFixedVariant => scheme.onTertiaryFixedVariant,
  };
}

/// Couleur sémantique persistée sous la forme `theme:primary`.
///
/// Compatible avec les propriétés Color existantes ; appeler [resolveThemeColor]
/// avant de la transmettre à Flutter ou de calculer une couleur dérivée.
@immutable
class ThemeColor extends Color {
  /// Crée une référence au rôle [role], sans figer sa valeur ARGB.
  const ThemeColor(this.role) : super(0);

  /// Rôle du ColorScheme, indépendant du thème actif.
  final ThemeColorRole role;

  /// Représentation JSON commune aux exports complets et compacts.
  String toJson() => 'theme:${role.name}';

  /// Représentation JSON compacte.
  String toCompactJson() => toJson();

  /// Vérifie les invariants de la référence typée.
  void validate() {}

  /// Copie cette référence avec un autre rôle.
  ThemeColor copyWith({ThemeColorRole? role}) => ThemeColor(role ?? this.role);

  @override
  int toARGB32() => throw StateError(
    'Résoudre ${toJson()} avec le ColorScheme local avant de lire sa valeur ARGB.',
  );

  /// Lit une référence, en rejetant les rôles inconnus.
  static ThemeColor fromJson(Object? value) {
    if (value is String && value.startsWith('theme:')) {
      final name = value.substring(6);
      for (final role in ThemeColorRole.values) {
        if (role.name == name) return ThemeColor(role);
      }
    }
    throw FormatException('Référence de couleur du thème invalide : $value.');
  }

  @override
  bool operator ==(Object other) => other is ThemeColor && other.role == role;

  @override
  int get hashCode => Object.hash(ThemeColor, role);
}

/// Résout une couleur sémantique sans modifier la configuration persistée.
Color resolveThemeColor(Color color, ColorScheme scheme) =>
    color is ThemeColor ? color.role.resolve(scheme) : color;

/// Résolution nullable des propriétés de couleur optionnelles.
Color? resolveOptionalThemeColor(Color? color, ColorScheme scheme) =>
    color == null ? null : resolveThemeColor(color, scheme);

/// Résolution locale des propriétés de couleur optionnelles des composants.
extension ThemeColorResolution on Color? {
  /// Observe le thème Flutter afin de reconstruire lors de ses changements.
  Color? resolveTheme(BuildContext context) =>
      resolveOptionalThemeColor(this, Theme.of(context).colorScheme);
}
