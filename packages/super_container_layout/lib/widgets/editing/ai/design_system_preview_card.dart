/// Widgets d'aperçu visuel et barre de contrôle de système de design pour le chat Vibe IA.
///
/// Définit le résultat de sélection immuable ([DesignSystemSelectionResult]), la miniature
/// d'interface peinte en conteneurs Flutter ([DesignSystemMiniPreview]), la carte de galerie
/// ([DesignSystemPreviewCard]) affichée dans `DesignSystemCatalogDialog`, ainsi que la barre
/// compacte ([VibeDesignSystemBar]) intégrée à l'en-tête de `VibeChatDialog`.
/// Interagit directement avec [DesignSystemPreset], [DesignSystemPalettePreview] et [DesignSystem].
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../../../ai/design_system_catalog.dart';
import '../../../theme/design_system.dart';

/// Résultat immuable renvoyé par la galerie `DesignSystemCatalogDialog` lors de la validation.
@immutable
class DesignSystemSelectionResult {
  /// Crée un résultat de sélection en protégeant [updatedCustomPresets] par `List.unmodifiable`.
  DesignSystemSelectionResult({
    required this.preset,
    required this.applyThemeTokensNow,
    required this.triggerImmediateRestyle,
    List<DesignSystemPreset> updatedCustomPresets = const [],
  }) : updatedCustomPresets = List<DesignSystemPreset>.unmodifiable(
         updatedCustomPresets,
       );

  /// Préréglage `DESIGN.md` retenu, ou `null` pour revenir au système Material 3 par défaut.
  final DesignSystemPreset? preset;

  /// Indique si le mode clair/sombre et la couleur d'accent doivent être appliqués immédiatement.
  final bool applyThemeTokensNow;

  /// Indique si un tour de restylage complet de l'écran courant doit être lancé aussitôt.
  final bool triggerImmediateRestyle;

  /// Liste non modifiable des préréglages `DESIGN.md` personnalisés importés durant la session.
  final List<DesignSystemPreset> updatedCustomPresets;

  /// Indique si la sélection correspond au guide Material 3 adaptatif par défaut (`preset == null`).
  bool get isDefault => preset == null;

  /// Retourne une copie de ce résultat avec les champs spécifiés remplacés.
  DesignSystemSelectionResult copyWith({
    DesignSystemPreset? preset,
    bool clearPreset = false,
    bool? applyThemeTokensNow,
    bool? triggerImmediateRestyle,
    List<DesignSystemPreset>? updatedCustomPresets,
  }) => DesignSystemSelectionResult(
    preset: clearPreset ? null : (preset ?? this.preset),
    applyThemeTokensNow: applyThemeTokensNow ?? this.applyThemeTokensNow,
    triggerImmediateRestyle:
        triggerImmediateRestyle ?? this.triggerImmediateRestyle,
    updatedCustomPresets: updatedCustomPresets ?? this.updatedCustomPresets,
  );

  /// Compare deux résultats de sélection valeur par valeur.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesignSystemSelectionResult &&
          preset == other.preset &&
          applyThemeTokensNow == other.applyThemeTokensNow &&
          triggerImmediateRestyle == other.triggerImmediateRestyle &&
          listEquals(updatedCustomPresets, other.updatedCustomPresets);

  /// Code de hachage cohérent avec [operator ==].
  @override
  int get hashCode => Object.hash(
    preset,
    applyThemeTokensNow,
    triggerImmediateRestyle,
    Object.hashAll(updatedCustomPresets),
  );
}

/// Miniature d'interface inspirée de `getdesign.md` illustrant visuellement la palette d'un [DesignSystemPreset].
class DesignSystemMiniPreview extends StatelessWidget {
  /// Crée une miniature d'interface à partir de [preset], de [palette], ou du thème Material 3 courant si tous deux sont nuls.
  const DesignSystemMiniPreview({
    this.preset,
    this.palette,
    this.height = 108,
    super.key,
  });

  /// Crée une miniature représentant le système adaptatif Material 3 par défaut du contexte courant.
  const DesignSystemMiniPreview.materialDefault({this.height = 108, super.key})
    : preset = null,
      palette = null;

  /// Préréglage optionnel dont la palette est prévisualisée (`null` pour le mode Material 3 par défaut).
  final DesignSystemPreset? preset;

  /// Surcharge optionnelle de palette utilisée lorsque l'on souhaite prévisualiser des jetons directs.
  final DesignSystemPalettePreview? palette;

  /// Hauteur totale de la miniature en pixels logiques (`108` par défaut).
  final double height;

  /// Construit une palette synthétique basée sur le [ColorScheme] Material 3 ambiant.
  static DesignSystemPalettePreview defaultPaletteOf(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return DesignSystemPalettePreview(
      mode: isDark ? ThemeMode.dark : ThemeMode.light,
      accent: scheme.primary,
      canvas: isDark
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
      surface: isDark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLowest,
      textPrimary: scheme.onSurface,
      textMuted: scheme.onSurfaceVariant,
      border: scheme.outlineVariant,
      cardRadius: 12,
      surfaceSystem: DesignSystem.material,
      fontHint: 'Material 3',
    );
  }

  static String? _surfaceSystemBadgeLabel(DesignSystem system) =>
      switch (system) {
        DesignSystem.material => null,
        DesignSystem.liquidGlass => 'Glass',
        DesignSystem.neumorphism => 'Neumorph',
      };

  static Color _contrastingOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF111111);

  /// Construit la miniature visuelle de la palette dans un conteneur contraint à [height].
  @override
  Widget build(BuildContext context) {
    final effectivePalette =
        palette ?? preset?.palette ?? defaultPaletteOf(context);
    final clampedCardRadius = effectivePalette.cardRadius
        .clamp(0.0, 20.0)
        .toDouble();
    final surfaceBadge = _surfaceSystemBadgeLabel(
      effectivePalette.surfaceSystem,
    );
    final modeLabel = effectivePalette.isDark ? 'Sombre' : 'Clair';
    final onAccent = _contrastingOn(effectivePalette.accent);
    final railColor = Color.lerp(
      effectivePalette.canvas,
      effectivePalette.surface,
      0.62,
    )!;
    final isGlass = effectivePalette.surfaceSystem == DesignSystem.liquidGlass;
    final isNeumorphic =
        effectivePalette.surfaceSystem == DesignSystem.neumorphism;

    final List<BoxShadow> cardShadows = isNeumorphic
        ? DesignSystem.neumorphicShadows(effectivePalette.canvas, 3, 0.34)
        : [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: effectivePalette.isDark ? 0.24 : 0.06,
              ),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ];

    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: effectivePalette.canvas,
          border: Border(
            bottom: BorderSide(
              color: effectivePalette.border.withValues(alpha: 0.75),
            ),
          ),
        ),
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barre supérieure miniature de fenêtre avec pastilles et badges.
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: effectivePalette.surface.withValues(
                    alpha: isGlass ? 0.55 : 0.72,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: effectivePalette.border.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _WindowDot(
                      color: effectivePalette.textMuted.withValues(alpha: 0.42),
                    ),
                    const SizedBox(width: 4),
                    _WindowDot(
                      color: effectivePalette.textMuted.withValues(alpha: 0.30),
                    ),
                    const SizedBox(width: 4),
                    _WindowDot(
                      color: effectivePalette.textMuted.withValues(alpha: 0.20),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (surfaceBadge != null) ...[
                                _MiniPreviewBadge(
                                  label: surfaceBadge,
                                  backgroundColor: effectivePalette.accent
                                      .withValues(alpha: 0.18),
                                  borderColor: effectivePalette.accent
                                      .withValues(alpha: 0.48),
                                  textColor: effectivePalette.textPrimary,
                                ),
                                const SizedBox(width: 4),
                              ],
                              _MiniPreviewBadge(
                                label: modeLabel,
                                backgroundColor: effectivePalette.canvas
                                    .withValues(alpha: 0.78),
                                borderColor: effectivePalette.border,
                                textColor: effectivePalette.textMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Scène miniature : rail latéral gauche + carte principale élevée.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 30,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: railColor,
                          borderRadius: BorderRadius.circular(
                            (clampedCardRadius * 0.55).clamp(0.0, 8.0),
                          ),
                          border: Border.all(
                            color: effectivePalette.border.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: effectivePalette.accent,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: effectivePalette.textMuted.withValues(
                                  alpha: 0.34,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: effectivePalette.textMuted.withValues(
                                  alpha: 0.22,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isGlass
                                ? Color.lerp(
                                    effectivePalette.surface,
                                    Colors.white,
                                    effectivePalette.isDark ? 0.08 : 0.25,
                                  )!.withValues(alpha: 0.88)
                                : effectivePalette.surface,
                            borderRadius: BorderRadius.circular(
                              clampedCardRadius,
                            ),
                            border: Border.all(
                              color: isGlass
                                  ? Color.lerp(
                                      effectivePalette.border,
                                      Colors.white,
                                      0.35,
                                    )!
                                  : effectivePalette.border,
                            ),
                            boxShadow: cardShadows,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FractionallySizedBox(
                                    widthFactor: 0.56,
                                    child: Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: effectivePalette.textPrimary,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  FractionallySizedBox(
                                    widthFactor: 0.88,
                                    child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: effectivePalette.textMuted
                                            .withValues(alpha: 0.55),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FractionallySizedBox(
                                    widthFactor: 0.64,
                                    child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: effectivePalette.textMuted
                                            .withValues(alpha: 0.36),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Container(
                                      width: 24,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: effectivePalette.textMuted
                                            .withValues(alpha: 0.24),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 38,
                                    height: 14,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: effectivePalette.accent,
                                      borderRadius: BorderRadius.circular(
                                        (clampedCardRadius * 0.45).clamp(
                                          0.0,
                                          99.0,
                                        ),
                                      ),
                                    ),
                                    child: Container(
                                      width: 18,
                                      height: 3.5,
                                      decoration: BoxDecoration(
                                        color: onAccent.withValues(alpha: 0.92),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 5.5,
    height: 5.5,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _MiniPreviewBadge extends StatelessWidget {
  const _MiniPreviewBadge({
    required this.label,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: borderColor, width: 0.8),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: TextStyle(
        fontSize: 9.5,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    ),
  );
}

/// Carte interactive représentant un [DesignSystemPreset] ou le système Material 3 par défaut.
class DesignSystemPreviewCard extends StatelessWidget {
  /// Crée une carte d'aperçu pour [preset] (ou pour `'Material 3 (Défaut)'` lorsque [preset] vaut `null`).
  const DesignSystemPreviewCard({
    required this.preset,
    required this.selected,
    required this.onTap,
    this.onInspect,
    this.previewHeight = 108,
    super.key,
  });

  /// Titre affiché lorsque [preset] vaut `null`.
  static const String defaultTitle = 'Material 3 (Défaut)';

  /// Accroche affichée lorsque [preset] vaut `null`.
  static const String defaultTagline =
      'Système adaptatif Material 3 par défaut de super_container_layout (tokens theme:*).';

  /// Préréglage représenté par la carte, ou `null` pour le système Material 3 par défaut.
  final DesignSystemPreset? preset;

  /// Indique si cette carte est actuellement sélectionnée dans le catalogue.
  final bool selected;

  /// Callback déclenché lors d'un clic sur la carte.
  final VoidCallback onTap;

  /// Callback optionnel ouvrant l'inspecteur du document `DESIGN.md` associé à [preset].
  final VoidCallback? onInspect;

  /// Hauteur de la zone [DesignSystemMiniPreview] en tête de carte.
  final double previewHeight;

  /// Construit la carte interactive de sélection et d'aperçu du système de design.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentPreset = preset;
    final effectivePalette =
        currentPreset?.palette ??
        DesignSystemMiniPreview.defaultPaletteOf(context);
    final swatches = effectivePalette.swatches;
    final title = currentPreset?.name ?? defaultTitle;
    final tagline = currentPreset?.tagline ?? defaultTagline;
    final categoryLabel = currentPreset?.category.label ?? 'Adaptatif';
    final cardKey = key != null
        ? null
        : (currentPreset != null
              ? ValueKey<String>('design-system-card-${currentPreset.id}')
              : const ValueKey<String>('design-system-card-default'));

    return Material(
      key: cardKey,
      color: selected
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.06),
              scheme.surfaceContainerLow,
            )
          : scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2.0 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesignSystemMiniPreview(
              preset: currentPreset,
              palette: effectivePalette,
              height: previewHeight,
            ),
            Flexible(
              fit: FlexFit.loose,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pastilles de couleurs + indicateur de sélection + bouton d'inspection.
                    SizedBox(
                      height: 24,
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const NeverScrollableScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final (index, swatch)
                                      in swatches.indexed) ...[
                                    if (index > 0) const SizedBox(width: 4),
                                    _ColorSwatchPill(color: swatch),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: scheme.primary,
                            ),
                          ],
                          if (currentPreset != null && onInspect != null) ...[
                            const SizedBox(width: 2),
                            IconButton(
                              key: ValueKey<String>(
                                'design-system-inspect-${currentPreset.id}',
                              ),
                              tooltip: 'Lire le fichier DESIGN.md',
                              onPressed: onInspect,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              constraints: const BoxConstraints.tightFor(
                                width: 24,
                                height: 24,
                              ),
                              icon: Icon(
                                Icons.description_outlined,
                                size: 16,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Titre du système de design.
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Puces de catégorie et d'import personnalisé.
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _MetadataChip(
                            label: categoryLabel,
                            backgroundColor: scheme.surfaceContainerHighest,
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          if (currentPreset != null &&
                              currentPreset.isCustom) ...[
                            const SizedBox(width: 4),
                            _MetadataChip(
                              label: 'Importé',
                              backgroundColor: scheme.tertiaryContainer,
                              foregroundColor: scheme.onTertiaryContainer,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Accroche descriptive limitée à 2 lignes.
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        tagline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.28,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatchPill extends StatelessWidget {
  const _ColorSwatchPill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final hex = DesignSystemPalettePreview.colorToHex(color);
    final isLightSwatch =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    final borderColor = isLightSwatch
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.24);
    return Tooltip(
      message: hex,
      child: Container(
        width: 20,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: foregroundColor,
      ),
    ),
  );
}

/// Barre compacte de sélection et d'application de `DESIGN.md` destinée à l'en-tête de `VibeChatDialog`.
class VibeDesignSystemBar extends StatelessWidget {
  /// Crée une barre compacte affichant le système actif et les actions associées.
  const VibeDesignSystemBar({
    required this.selectedPreset,
    required this.onOpenCatalog,
    this.onClear,
    this.onRestyle,
    this.sending = false,
    super.key,
  });

  /// Système de design actuellement actif, ou `null` pour `'Material 3 (Défaut)'`.
  final DesignSystemPreset? selectedPreset;

  /// Désactive l'ensemble des actions pendant qu'une génération IA est en cours.
  final bool sending;

  /// Callback ouvrant le dialogue de galerie `DesignSystemCatalogDialog`.
  final VoidCallback? onOpenCatalog;

  /// Callback réinitialisant le système de design vers `'Material 3 (Défaut)'`.
  final VoidCallback? onClear;

  /// Callback déclenchant le restylage immédiat de l'écran selon [selectedPreset].
  final VoidCallback? onRestyle;

  /// Construit la barre compacte de sélection et de restylage pour l'en-tête du chat Vibe.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preset = selectedPreset;
    final label =
        'Design : ${preset?.name ?? DesignSystemPreviewCard.defaultTitle}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final showModeBadge =
            preset != null &&
            (!constraints.maxWidth.isFinite || constraints.maxWidth >= 260);
        return Row(
          children: [
            Flexible(
              child: Material(
                color: preset != null
                    ? scheme.secondaryContainer.withValues(alpha: 0.72)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: const ValueKey('vibe-chat-design-system-button'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: sending ? null : onOpenCatalog,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preset != null)
                          _PresetMiniDots(palette: preset.palette)
                        else
                          Icon(
                            Icons.palette_outlined,
                            size: 15,
                            color: sending
                                ? scheme.onSurface.withValues(alpha: 0.38)
                                : scheme.onSurfaceVariant,
                          ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sending
                                  ? scheme.onSurface.withValues(alpha: 0.38)
                                  : (preset != null
                                        ? scheme.onSecondaryContainer
                                        : scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        if (showModeBadge) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              preset.palette.isDark ? 'Sombre' : 'Clair',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: sending
                                    ? scheme.onSurface.withValues(alpha: 0.38)
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 3),
                        Icon(
                          Icons.unfold_more,
                          size: 15,
                          color: sending
                              ? scheme.onSurface.withValues(alpha: 0.38)
                              : scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (preset != null) ...[
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('vibe-chat-clear-design-system'),
                tooltip: 'Revenir au Design System par défaut',
                onPressed: sending ? null : onClear,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                iconSize: 15,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 26,
                ),
                icon: const Icon(Icons.close, size: 15),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Restyler l’écran actuel selon ${preset.name}',
                child: FilledButton.tonalIcon(
                  key: const ValueKey('vibe-chat-restyle-screen'),
                  onPressed: sending ? null : onRestyle,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 28),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 15),
                  label: const Text('Restyler'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PresetMiniDots extends StatelessWidget {
  const _PresetMiniDots({required this.palette});

  final DesignSystemPalettePreview palette;

  @override
  Widget build(BuildContext context) {
    final colors = [palette.canvas, palette.surface, palette.accent];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, color) in colors.indexed) ...[
          if (index > 0) const SizedBox(width: 2),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.light
                    ? Colors.black.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.28),
                width: 0.8,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
