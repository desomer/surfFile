import 'dart:ui' show Offset;

/// Retour visuel d'un conteneur au clic ; un seul effet à la fois. L'effet au
/// survol est indépendant (ContainerStyle.hoverEffect).
enum InteractionEffect {
  ripple('Onde au clic (Ripple)', 'Onde Material qui part du clic'),
  pressed('Effet à l’appui (Pressed)', 'Voile et léger retrait à l’appui'),
  elevation('Changement d’élévation', 'S’élève au survol, s’enfonce à l’appui');

  const InteractionEffect(this.label, this.description);

  final String label;
  final String description;

  /// Durée des transitions de l'effet.
  static const duration = Duration(milliseconds: 150);

  /// Opacité du voile au survol (gris Material) et teintée (accent, perso).
  static const hoverOverlay = .08;
  static const hoverTintedOverlay = .14;

  /// Opacité du voile à l'appui pour [pressed].
  static const pressedOverlay = .16;

  /// Surélévation au survol pour [elevation].
  static const hoverLift = 4.0;

  /// Décalage, flou et opacité de l'ombre intérieure à l'appui pour
  /// [elevation] : la surface perd son ombre portée et paraît enfoncée.
  static const insetOffset = 3.0;
  static const insetBlur = 4.0;
  static const insetShadowOpacity = .35;
  static const insetLightOpacity = .18;

  /// Translation de la surface à l'appui pour [elevation], dans le sens de
  /// l'ombre intérieure, pour renforcer l'enfoncement.
  static const sinkOffset = Offset(1, 1.5);

  /// Retrait de l'échelle à l'appui pour [pressed].
  static const pressedScale = .985;
}

/// Couleur du voile de l'effet au survol.
enum HoverTint {
  material('Material (gris neutre)'),
  accent('Couleur d’accent'),
  custom('Couleur personnalisée');

  const HoverTint(this.label);

  final String label;
}
