import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/container_fill.dart';
import '../theme/design_system.dart';
import '../theme/interaction_effect.dart';
import '../theme/neon_style.dart';
import 'neon_surface.dart';

class ContainerStyleEditor extends StatelessWidget {
  const ContainerStyleEditor({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.solidColor,
    this.radius = 13,
    this.borderWidth = 1,
    this.borderColor,
    this.elevation = 0,
    this.shadowOpacity = .2,
    this.opacity = 1,
    this.collapsible = true,
    this.onSolidColorChanged,
    this.onRadiusChanged,
    this.onBorderWidthChanged,
    this.onBorderColorChanged,
    this.onResetBorderColor,
    this.onElevationChanged,
    this.onShadowOpacityChanged,
    this.padding = 0,
    this.margin = 0,
    this.onPaddingChanged,
    this.onMarginChanged,
    this.neon = const NeonStyle(),
    this.accent = const Color(0xFF5268D9),
    this.onNeonChanged,
    this.designSystem = DesignSystem.material,
    this.onDesignSystemChanged,
    this.interactionEffect = InteractionEffect.ripple,
    this.onInteractionEffectChanged,
    this.hoverEffect = false,
    this.onHoverEffectChanged,
    this.hoverTint = HoverTint.material,
    this.hoverColor,
    this.onHoverTintChanged,
    this.onHoverColorChanged,
    super.key,
  });

  /// Système de design ; le sélecteur n'apparaît que si
  /// [onDesignSystemChanged] est fourni.
  final DesignSystem designSystem;
  final ValueChanged<DesignSystem>? onDesignSystemChanged;

  /// Effet à l'interaction ; le sélecteur n'apparaît que si
  /// [onInteractionEffectChanged] est fourni.
  final InteractionEffect interactionEffect;
  final ValueChanged<InteractionEffect>? onInteractionEffectChanged;

  /// Effet au survol, indépendant du choix ci-dessus ; la case n'apparaît que
  /// si [onHoverEffectChanged] est fourni.
  final bool hoverEffect;
  final ValueChanged<bool>? onHoverEffectChanged;

  /// Couleur du voile au survol, proposée quand l'effet est actif.
  final HoverTint hoverTint;
  final Color? hoverColor;
  final ValueChanged<HoverTint>? onHoverTintChanged;
  final ValueChanged<Color>? onHoverColorChanged;

  final String label;
  final ContainerFill value;
  final ValueChanged<ContainerFill> onChanged;
  final Color solidColor;
  final double radius;
  final double borderWidth;
  final Color? borderColor;
  final double elevation;
  final double shadowOpacity;
  final double opacity;
  final bool collapsible;
  final ValueChanged<Color>? onSolidColorChanged;
  final ValueChanged<double>? onRadiusChanged;
  final ValueChanged<double>? onBorderWidthChanged;
  final ValueChanged<Color>? onBorderColorChanged;
  final VoidCallback? onResetBorderColor;
  final ValueChanged<double>? onElevationChanged;
  final ValueChanged<double>? onShadowOpacityChanged;
  final double padding;
  final double margin;
  final ValueChanged<double>? onPaddingChanged;
  final ValueChanged<double>? onMarginChanged;
  final NeonStyle neon;
  final Color accent;
  final ValueChanged<NeonStyle>? onNeonChanged;

  @override
  Widget build(BuildContext context) {
    final children = [
      if (onDesignSystemChanged != null) ...[
        DropdownButtonFormField<DesignSystem>(
          key: ValueKey('design-system-$label'),
          initialValue: designSystem,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Système de design',
            helperText: 'Règle l’arrondi, la bordure, l’ombre et le fond.',
          ),
          items: [
            for (final system in DesignSystem.values)
              DropdownMenuItem(
                value: system,
                child: Text(system.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (system) {
            if (system != null) onDesignSystemChanged!(system);
          },
        ),
        const SizedBox(height: 8),
      ],
      if (onInteractionEffectChanged != null) ...[
        DropdownButtonFormField<InteractionEffect>(
          key: ValueKey('interaction-effect-$label'),
          initialValue: interactionEffect,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Effet d’interaction',
            helperText: interactionEffect.description,
          ),
          items: [
            for (final effect in InteractionEffect.values)
              DropdownMenuItem(
                value: effect,
                child: Text(effect.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (effect) {
            if (effect != null) onInteractionEffectChanged!(effect);
          },
        ),
      ],
      if (onHoverEffectChanged != null)
        CheckboxListTile(
          key: ValueKey('hover-effect-$label'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Effet au survol (Hover)'),
          subtitle: const Text('Voile quand le pointeur survole'),
          value: hoverEffect,
          onChanged: (v) => onHoverEffectChanged!(v ?? false),
        ),
      if (hoverEffect &&
          onHoverEffectChanged != null &&
          onHoverTintChanged != null) ...[
        DropdownButtonFormField<HoverTint>(
          key: ValueKey('hover-tint-$label'),
          initialValue: hoverTint,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Couleur du survol'),
          items: [
            for (final tint in HoverTint.values)
              DropdownMenuItem(
                value: tint,
                child: Text(tint.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (tint) {
            if (tint != null) onHoverTintChanged!(tint);
          },
        ),
        if (hoverTint == HoverTint.custom && onHoverColorChanged != null)
          _color(
            'Couleur du voile',
            hoverColor ?? accent,
            onHoverColorChanged!,
          ),
      ],
      const SizedBox(height: 8),
      DropdownButtonFormField<FillType>(
        initialValue: value.type,
        decoration: const InputDecoration(labelText: 'Type de fond'),
        items: const [
          DropdownMenuItem(value: FillType.solid, child: Text('Couleur unie')),
          DropdownMenuItem(value: FillType.linear, child: Text('Linéaire')),
          DropdownMenuItem(value: FillType.radial, child: Text('Radial')),
          DropdownMenuItem(value: FillType.sweep, child: Text('Circulaire')),
        ],
        onChanged: (type) {
          if (type != null) onChanged(value.copyWith(type: type));
        },
      ),
      if (value.type == FillType.solid && onSolidColorChanged != null)
        _color('Couleur unie', solidColor, onSolidColorChanged!),
      if (value.type != FillType.solid) ...[
        _color(
          'Couleur de départ',
          value.start,
          (color) => onChanged(value.copyWith(start: color)),
        ),
        _color(
          'Couleur d’arrivée',
          value.end,
          (color) => onChanged(value.copyWith(end: color)),
        ),
        if (value.type != FillType.radial)
          _slider(
            'Orientation (°)',
            value.angle,
            0,
            360,
            (angle) => onChanged(value.copyWith(angle: angle)),
          ),
        if (value.type == FillType.radial)
          _slider(
            'Rayon du dégradé',
            value.radius,
            .1,
            2,
            (radius) => onChanged(value.copyWith(radius: radius)),
          ),
      ],
      if (onRadiusChanged != null)
        _slider('Arrondi du conteneur', radius, 0, 36, onRadiusChanged!),
      if (onBorderWidthChanged != null)
        _slider(
          'Bordure du conteneur',
          borderWidth,
          0,
          4,
          onBorderWidthChanged!,
        ),
      if (onBorderColorChanged != null)
        _color(
          'Couleur de la bordure',
          borderColor ?? Theme.of(context).colorScheme.outlineVariant,
          onBorderColorChanged!,
        ),
      if (onResetBorderColor != null)
        TextButton(
          key: ValueKey('automatic-border-$label'),
          onPressed: onResetBorderColor,
          child: const Text('Couleur de bordure automatique'),
        ),
      if (onElevationChanged != null)
        _slider(
          'Élévation du conteneur',
          elevation,
          0,
          16,
          onElevationChanged!,
        ),
      if (onShadowOpacityChanged != null)
        _slider(
          'Opacité de l’ombre du conteneur',
          shadowOpacity,
          0,
          .6,
          onShadowOpacityChanged!,
        ),
      if (onPaddingChanged != null)
        _slider(
          'Marge intérieure (padding)',
          padding,
          0,
          48,
          onPaddingChanged!,
          key: ValueKey('padding-$label'),
        ),
      if (onMarginChanged != null)
        _slider(
          'Marge extérieure (margin)',
          margin,
          0,
          48,
          onMarginChanged!,
          key: ValueKey('margin-$label'),
        ),
      const SizedBox(height: 12),
      if (onNeonChanged != null)
        NeonStyleEditor(
          label: label,
          value: neon,
          accent: accent,
          onChanged: onNeonChanged!,
        ),
      Padding(
        padding: neon.enabled ? const EdgeInsets.all(18) : EdgeInsets.zero,
        child: NeonSurface(
          style: neon,
          accent: accent,
          radius: radius,
          child: Container(
            key: ValueKey('preview-$label'),
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              color: value.type == FillType.solid
                  ? solidColor.withValues(alpha: solidColor.a * opacity)
                  : null,
              gradient: value.gradient(opacity: opacity),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color:
                    borderColor ?? Theme.of(context).colorScheme.outlineVariant,
                width: borderWidth,
                style: borderWidth == 0 ? BorderStyle.none : BorderStyle.solid,
              ),
              boxShadow: elevation == 0
                  ? null
                  : designSystem == DesignSystem.neumorphism
                  ? DesignSystem.neumorphicShadows(
                      solidColor,
                      elevation,
                      shadowOpacity,
                    )
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: shadowOpacity),
                        blurRadius: elevation * 2,
                        offset: Offset(0, elevation / 2),
                      ),
                    ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
    if (!collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ExpansionTile(
      key: ValueKey(label),
      title: Text(label),
      subtitle: Text(switch (value.type) {
        FillType.solid => 'Couleur unie',
        FillType.linear => 'Dégradé linéaire',
        FillType.radial => 'Dégradé radial',
        FillType.sweep => 'Dégradé circulaire',
      }),
      childrenPadding: const EdgeInsets.all(12),
      children: children,
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    Key? key,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('$label : ${value.toStringAsFixed(1)}'),
      Slider(key: key, value: value, min: min, max: max, onChanged: onChanged),
    ],
  );
}

class NeonStyleEditor extends StatelessWidget {
  const NeonStyleEditor({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    super.key,
  });

  final String label;
  final NeonStyle value;
  final Color accent;
  final ValueChanged<NeonStyle> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        key: ValueKey('neon-$label'),
        title: const Text('Effet néon'),
        subtitle: const Text('Halo lumineux sans bordure supplémentaire'),
        value: value.enabled,
        onChanged: (enabled) => onChanged(value.copyWith(enabled: enabled)),
      ),
      if (value.enabled) ...[
        _color(
          'Couleur du néon',
          value.color ?? accent,
          (color) => onChanged(value.copyWith(color: color)),
        ),
        TextButton(
          onPressed: () => onChanged(value.copyWith(resetColor: true)),
          child: const Text('Utiliser la couleur d’accent'),
        ),
        Text('Intensité : ${(value.intensity * 100).round()} %'),
        Slider(
          key: ValueKey('neon-intensity-$label'),
          value: value.intensity,
          max: NeonStyle.maxIntensity,
          onChanged: (intensity) =>
              onChanged(value.copyWith(intensity: intensity)),
        ),
      ],
    ],
  );
}

Widget _color(String label, Color color, ValueChanged<Color> onChanged) =>
    styleColorTile(label, color, onChanged);

/// Ligne repliable avec pastille et sélecteur de couleur (palette, roue).
Widget styleColorTile(
  String label,
  Color color,
  ValueChanged<Color> onChanged, {
  Key? key,
}) => ExpansionTile(
  key: key,
  title: Text(label),
  leading: CircleAvatar(backgroundColor: color, radius: 12),
  children: [
    ColorPicker(
      color: color,
      onColorChanged: onChanged,
      enableOpacity: true,
      showColorCode: true,
      showEditIconButton: true,
      opacitySubheading: const Text('Opacité'),
      width: 30,
      height: 30,
      wheelDiameter: 180,
      pickersEnabled: const {
        ColorPickerType.both: true,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.wheel: true,
      },
      pickerTypeLabels: const {
        ColorPickerType.both: 'Palette',
        ColorPickerType.wheel: 'Roue',
      },
    ),
  ],
);
