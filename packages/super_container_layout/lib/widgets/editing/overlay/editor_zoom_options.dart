/// Options immuables et seuils par défaut du zoom et du cadrage automatique.
library;

import 'package:material_ui/material_ui.dart';

/// Options immuables configurant le comportement du zoom et du cadrage automatique
/// en mode édition.
@immutable
class EditorZoomOptions {
  /// Échelle minimale utilisée par le contrôleur de zoom.
  static const double defaultMinScale = 1.0;

  /// Échelle maximale par défaut du contrôleur et de ses options.
  static const double defaultMaxScale = 4.0;

  /// Fraction d'écran visée par le cadrage automatique par défaut.
  static const double defaultTargetScreenAreaFraction = 1.0 / 3.0;

  /// Crée une configuration d'options de zoom pour le mode édition.
  const EditorZoomOptions({
    this.skipLargeElementsOnRightClick = true,
    this.skipLargeElementsOnDialog = true,
    this.largeElementViewportThreshold = defaultLargeElementThreshold,
    this.zoomOnRightClick = true,
    this.zoomOnHover = true,
    this.zoomOnSelection = true,
    this.zoomOnEditorDialog = true,
    this.resetZoomOnDialogExit = true,
    this.minDialogScale = defaultMinDialogScale,
    this.maxScale = defaultMaxScale,
    this.targetScreenAreaFraction = defaultTargetScreenAreaFraction,
    this.animateTransitions = true,
    this.animationDurationMs = defaultAnimationDurationMs,
  });

  /// Seuil par défaut (`0.70`, soit 70% de l'écran) au-delà duquel un élément
  /// est considéré comme trop grand pour le zoom au clic droit ou l'ouverture des propriétés.
  static const double defaultLargeElementThreshold = 0.70;

  /// Échelle minimale par défaut (`0.50`, soit 50%) lors du dézoom à côté d'une
  /// boîte de dialogue de propriétés.
  static const double defaultMinDialogScale = 0.50;

  /// Durée par défaut de l'animation de transition du zoom (en millisecondes).
  static const int defaultAnimationDurationMs = 300;

  /// Conserve la vue actuelle sans zoomer ni déplacer le canevas lors d'un clic
  /// droit sur un élément dépassant [largeElementViewportThreshold].
  final bool skipLargeElementsOnRightClick;

  /// Conserve la vue actuelle sans dézoomer lors de l'ouverture d'une boîte de
  /// dialogue de propriétés sur un élément dépassant [largeElementViewportThreshold].
  final bool skipLargeElementsOnDialog;

  /// Proportion maximale (entre `0.30` et `1.0`) du canevas au-delà de laquelle
  /// un élément est considéré comme trop grand.
  final double largeElementViewportThreshold;

  /// Active le zoom et le recadrage automatique lors de l'ouverture du menu
  /// contextuel au clic droit.
  final bool zoomOnRightClick;

  /// Active le zoom/cadrage automatique lors du survol des entrées du menu
  /// contextuel ou de l'arbre de sélection.
  final bool zoomOnHover;

  /// Active le zoom automatique lors de la sélection d'un composant ou d'une
  /// zone sur le canevas.
  final bool zoomOnSelection;

  /// Active le recadrage automatique à côté des boîtes de dialogue d'édition.
  final bool zoomOnEditorDialog;

  /// Retourne automatiquement au zoom et à la position d'avant l'ouverture
  /// de la fenêtre de saisie des propriétés lors de sa fermeture.
  final bool resetZoomOnDialogExit;

  /// Facteur de dézoom minimal autorisé lorsqu'une boîte de dialogue d'édition
  /// est ouverte (entre `0.30` et `1.0`).
  final double minDialogScale;

  /// Facteur de zoom automatique maximal (entre `1.5` et `4.0`).
  final double maxScale;

  /// Fraction cible de la surface d'écran occupée par l'élément zoomé
  /// (entre `0.15` et `0.75`).
  final double targetScreenAreaFraction;

  /// Active les animations fluides lors des transitions de zoom et de cadrage.
  final bool animateTransitions;

  /// Durée de l'animation de zoom en millisecondes (entre `50` et `600`).
  final int animationDurationMs;

  /// Indique si [targetRect] dépasse le seuil [largeElementViewportThreshold]
  /// par rapport à la taille [viewportSize] du canevas.
  bool isElementTooLarge(Rect targetRect, Size viewportSize) {
    if (viewportSize.isEmpty || targetRect.isEmpty || !targetRect.isFinite) {
      return false;
    }
    final threshold = largeElementViewportThreshold.clamp(0.10, 1.0);
    final widthRatio = (targetRect.width / viewportSize.width).clamp(0.0, 1.0);
    final heightRatio = (targetRect.height / viewportSize.height).clamp(
      0.0,
      1.0,
    );
    final areaRatio = widthRatio * heightRatio;
    return (widthRatio >= threshold && heightRatio >= threshold) ||
        areaRatio >= threshold;
  }

  /// Retourne une copie de ces options avec les champs spécifiés mis à jour.
  EditorZoomOptions copyWith({
    bool? skipLargeElementsOnRightClick,
    bool? skipLargeElementsOnDialog,
    double? largeElementViewportThreshold,
    bool? zoomOnRightClick,
    bool? zoomOnHover,
    bool? zoomOnSelection,
    bool? zoomOnEditorDialog,
    bool? resetZoomOnDialogExit,
    double? minDialogScale,
    double? maxScale,
    double? targetScreenAreaFraction,
    bool? animateTransitions,
    int? animationDurationMs,
  }) => EditorZoomOptions(
    skipLargeElementsOnRightClick:
        skipLargeElementsOnRightClick ?? this.skipLargeElementsOnRightClick,
    skipLargeElementsOnDialog:
        skipLargeElementsOnDialog ?? this.skipLargeElementsOnDialog,
    largeElementViewportThreshold:
        largeElementViewportThreshold ?? this.largeElementViewportThreshold,
    zoomOnRightClick: zoomOnRightClick ?? this.zoomOnRightClick,
    zoomOnHover: zoomOnHover ?? this.zoomOnHover,
    zoomOnSelection: zoomOnSelection ?? this.zoomOnSelection,
    zoomOnEditorDialog: zoomOnEditorDialog ?? this.zoomOnEditorDialog,
    resetZoomOnDialogExit: resetZoomOnDialogExit ?? this.resetZoomOnDialogExit,
    minDialogScale: minDialogScale ?? this.minDialogScale,
    maxScale: maxScale ?? this.maxScale,
    targetScreenAreaFraction:
        targetScreenAreaFraction ?? this.targetScreenAreaFraction,
    animateTransitions: animateTransitions ?? this.animateTransitions,
    animationDurationMs: animationDurationMs ?? this.animationDurationMs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorZoomOptions &&
          other.skipLargeElementsOnRightClick ==
              skipLargeElementsOnRightClick &&
          other.skipLargeElementsOnDialog == skipLargeElementsOnDialog &&
          other.largeElementViewportThreshold ==
              largeElementViewportThreshold &&
          other.zoomOnRightClick == zoomOnRightClick &&
          other.zoomOnHover == zoomOnHover &&
          other.zoomOnSelection == zoomOnSelection &&
          other.zoomOnEditorDialog == zoomOnEditorDialog &&
          other.resetZoomOnDialogExit == resetZoomOnDialogExit &&
          other.minDialogScale == minDialogScale &&
          other.maxScale == maxScale &&
          other.targetScreenAreaFraction == targetScreenAreaFraction &&
          other.animateTransitions == animateTransitions &&
          other.animationDurationMs == animationDurationMs;

  @override
  int get hashCode => Object.hash(
    skipLargeElementsOnRightClick,
    skipLargeElementsOnDialog,
    largeElementViewportThreshold,
    zoomOnRightClick,
    zoomOnHover,
    zoomOnSelection,
    zoomOnEditorDialog,
    resetZoomOnDialogExit,
    minDialogScale,
    maxScale,
    targetScreenAreaFraction,
    animateTransitions,
    animationDurationMs,
  );
}
