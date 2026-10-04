import 'package:material_ui/material_ui.dart';

import '../theme/container_style.dart';
import '../theme/style_extras.dart';
import 'container_style_editor.dart' show styleColorTile;
import 'style_editor_panel.dart';

/// Réglages de forme et d'aspect ajoutés au style de base : coins et côtés
/// indépendants, ombres détaillées, opacité, flou, motif et transformation.
/// Chaque méthode renvoie le contenu d'une carte de l'éditeur.
class StyleExtrasControls {
  const StyleExtrasControls({
    required this.label,
    required this.style,
    required this.onStyle,
  });

  final String label;
  final ContainerStyle style;
  final ValueChanged<ContainerStyle> onStyle;

  static const _corners = [
    'Haut gauche',
    'Haut droit',
    'Bas droit',
    'Bas gauche',
  ];
  static const _sides = ['Haut', 'Droite', 'Bas', 'Gauche'];

  List<Widget> _quad({
    required String id,
    required List<String> names,
    required Quad value,
    required double max,
    required ValueChanged<Quad> onChanged,
  }) => [
    for (var i = 0; i < 4; i += 2)
      StylePair(
        StyleSliderField(
          label: names[i],
          value: value[i],
          min: 0,
          max: max,
          sliderKey: ValueKey('$id-$i-$label'),
          onChanged: (v) => onChanged(value.withAt(i, v)),
        ),
        StyleSliderField(
          label: names[i + 1],
          value: value[i + 1],
          min: 0,
          max: max,
          sliderKey: ValueKey('$id-${i + 1}-$label'),
          onChanged: (v) => onChanged(value.withAt(i + 1, v)),
        ),
      ),
  ];

  /// Rayon uniforme ([uniform]) ou un rayon par coin.
  List<Widget> radius(List<Widget> uniform) {
    final radii = style.radii;
    return [
      if (radii == null) ...uniform,
      StyleSwitchField(
        key: ValueKey('radii-switch-$label'),
        title: 'Coins indépendants',
        value: radii != null,
        onChanged: (on) =>
            onStyle(style.copyWith(radii: on ? Quad.all(style.radius) : null)),
      ),
      if (radii != null)
        ..._quad(
          id: 'radii',
          names: _corners,
          value: radii,
          max: 36,
          onChanged: (v) => onStyle(style.copyWith(radii: v)),
        ),
    ];
  }

  /// Épaisseur uniforme ou par côté, et type de trait.
  List<Widget> border(List<Widget> uniform, {required bool hasWidth}) {
    final widths = style.borderWidths;
    return [
      if (widths == null) ...uniform,
      if (hasWidth)
        StyleSwitchField(
          key: ValueKey('border-sides-switch-$label'),
          title: 'Côtés indépendants',
          value: widths != null,
          onChanged: (on) => onStyle(
            style.copyWith(
              borderWidths: on ? Quad.all(style.borderWidth) : null,
            ),
          ),
        ),
      if (widths != null)
        ..._quad(
          id: 'border-side',
          names: _sides,
          value: widths,
          max: 4,
          onChanged: (v) => onStyle(style.copyWith(borderWidths: v)),
        ),
      DropdownButtonFormField<BorderLine>(
        key: ValueKey('border-line-$label'),
        initialValue: style.borderLine,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Type de trait'),
        items: [
          for (final line in BorderLine.values)
            DropdownMenuItem(value: line, child: Text(line.label)),
        ],
        onChanged: (line) {
          if (line != null) onStyle(style.copyWith(borderLine: line));
        },
      ),
    ];
  }

  List<Widget> _shadowSpec(
    ShadowSpec spec,
    ValueChanged<ShadowSpec> onChanged,
    String id,
    String enableLabel,
  ) => [
    StyleSwitchField(
      key: ValueKey('$id-enabled-$label'),
      title: enableLabel,
      value: spec.enabled,
      onChanged: (v) => onChanged(spec.copyWith(enabled: v)),
    ),
    styleColorTile(
      'Couleur de l’ombre',
      spec.color,
      (color) => onChanged(spec.copyWith(color: color)),
      dense: true,
    ),
    StyleSliderField(
      label: 'Opacité',
      value: spec.opacity * 100,
      min: 0,
      max: 100,
      unit: ' %',
      sliderKey: ValueKey('$id-opacity-$label'),
      onChanged: (v) => onChanged(spec.copyWith(opacity: v / 100)),
    ),
    StylePair(
      StyleSliderField(
        label: 'Flou',
        value: spec.blur,
        min: 0,
        max: ShadowSpec.maxBlur,
        sliderKey: ValueKey('$id-blur-$label'),
        onChanged: (v) => onChanged(spec.copyWith(blur: v)),
      ),
      StyleSliderField(
        label: 'Étalement',
        value: spec.spread,
        min: -ShadowSpec.maxSpread,
        max: ShadowSpec.maxSpread,
        sliderKey: ValueKey('$id-spread-$label'),
        onChanged: (v) => onChanged(spec.copyWith(spread: v)),
      ),
    ),
    StylePair(
      StyleSliderField(
        label: 'Décalage X',
        value: spec.dx,
        min: -ShadowSpec.maxOffset,
        max: ShadowSpec.maxOffset,
        sliderKey: ValueKey('$id-dx-$label'),
        onChanged: (v) => onChanged(spec.copyWith(dx: v)),
      ),
      StyleSliderField(
        label: 'Décalage Y',
        value: spec.dy,
        min: -ShadowSpec.maxOffset,
        max: ShadowSpec.maxOffset,
        sliderKey: ValueKey('$id-dy-$label'),
        onChanged: (v) => onChanged(spec.copyWith(dy: v)),
      ),
    ),
  ];

  /// Élévation Material ([elevation]) ou ombre portée détaillée.
  List<Widget> dropShadow(List<Widget> elevation) {
    final shadow = style.shadow;
    return [
      if (shadow == null) ...elevation,
      StyleSwitchField(
        key: ValueKey('shadow-detail-switch-$label'),
        title: 'Ombre détaillée',
        subtitle: 'Couleur, flou, étalement et décalage',
        value: shadow != null,
        onChanged: (on) => onStyle(
          style.copyWith(
            shadow: on
                ? ShadowSpec.fromElevation(style.elevation, style.shadowOpacity)
                : null,
          ),
        ),
      ),
      if (shadow != null)
        ..._shadowSpec(
          shadow,
          (v) => onStyle(style.copyWith(shadow: v)),
          'shadow',
          'Ombre activée',
        ),
    ];
  }

  List<Widget> innerShadow() {
    final shadow = style.innerShadow;
    return [
      StyleSwitchField(
        key: ValueKey('inner-shadow-switch-$label'),
        title: 'Ombre intérieure',
        subtitle: 'Surface en creux',
        value: shadow?.enabled ?? false,
        onChanged: (on) => onStyle(
          style.copyWith(
            innerShadow:
                (shadow ?? const ShadowSpec(opacity: .3, blur: 8, dx: 2, dy: 3))
                    .copyWith(enabled: on),
          ),
        ),
      ),
      if (shadow != null && shadow.enabled)
        ..._shadowSpec(
          shadow,
          (v) => onStyle(style.copyWith(innerShadow: v)),
          'inner',
          'Ombre intérieure activée',
        ),
    ];
  }

  /// Marge ou padding uniforme ([uniform]) ou par côté.
  List<Widget> spacing(List<Widget> uniform, {required bool padding}) {
    final value = padding ? style.paddingInsets : style.marginInsets;
    final scalar = padding ? style.padding : style.margin;
    return [
      if (value == null) ...uniform,
      StyleSwitchField(
        key: ValueKey('${padding ? 'padding' : 'margin'}-sides-switch-$label'),
        title: 'Côtés indépendants',
        value: value != null,
        onChanged: (on) {
          final next = on ? Quad.all(scalar) : null;
          onStyle(
            padding
                ? style.copyWith(paddingInsets: next)
                : style.copyWith(marginInsets: next),
          );
        },
      ),
      if (value != null)
        ..._quad(
          id: padding ? 'padding-side' : 'margin-side',
          names: _sides,
          value: value,
          max: ContainerStyle.maxSpacing,
          onChanged: (v) => onStyle(
            padding
                ? style.copyWith(paddingInsets: v)
                : style.copyWith(marginInsets: v),
          ),
        ),
    ];
  }

  /// Opacité de la surface et flou de l'arrière-plan.
  List<Widget> opacityAndBlur() {
    final blur = style.backdropBlur;
    return [
      StyleSliderField(
        label: 'Opacité',
        value: style.opacity * 100,
        min: 0,
        max: 100,
        unit: ' %',
        sliderKey: ValueKey('opacity-$label'),
        onChanged: (v) => onStyle(style.copyWith(opacity: v / 100)),
      ),
      StyleSwitchField(
        key: ValueKey('blur-switch-$label'),
        title: 'Flou d’arrière-plan',
        subtitle: blur == null
            ? 'Automatique : selon le système de design'
            : 'Réglé à la main',
        value: blur != null,
        onChanged: (on) => onStyle(
          style.copyWith(backdropBlur: on ? style.effectiveBackdropBlur : null),
        ),
      ),
      if (blur != null)
        StyleSliderField(
          label: 'Intensité du flou',
          value: blur,
          min: 0,
          max: ContainerStyle.maxBlur,
          unit: '',
          sliderKey: ValueKey('blur-$label'),
          onChanged: (v) => onStyle(style.copyWith(backdropBlur: v)),
        ),
    ];
  }

  List<Widget> pattern() => [
    DropdownButtonFormField<SurfacePattern>(
      key: ValueKey('pattern-$label'),
      initialValue: style.pattern,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Motif de fond'),
      items: [
        for (final kind in SurfacePattern.values)
          DropdownMenuItem(value: kind, child: Text(kind.label)),
      ],
      onChanged: (kind) {
        if (kind != null) onStyle(style.copyWith(pattern: kind));
      },
    ),
    if (style.pattern != SurfacePattern.none)
      StyleSliderField(
        label: 'Opacité du motif',
        value: style.patternOpacity * 100,
        min: 0,
        max: 100,
        unit: ' %',
        sliderKey: ValueKey('pattern-opacity-$label'),
        onChanged: (v) => onStyle(style.copyWith(patternOpacity: v / 100)),
      ),
  ];

  List<Widget> transform() {
    final value = style.transform;
    void change(TransformSpec v) => onStyle(style.copyWith(transform: v));
    return [
      StyleSwitchField(
        key: ValueKey('transform-switch-$label'),
        title: 'Transformation',
        subtitle: value == null ? 'Neutre' : 'Translation, rotation et échelle',
        value: value != null,
        onChanged: (on) => onStyle(
          style.copyWith(transform: on ? const TransformSpec() : null),
        ),
      ),
      if (value != null) ...[
        StylePair(
          StyleSliderField(
            label: 'Translation X',
            value: value.dx,
            min: -TransformSpec.maxOffset,
            max: TransformSpec.maxOffset,
            sliderKey: ValueKey('transform-dx-$label'),
            onChanged: (v) => change(value.copyWith(dx: v)),
          ),
          StyleSliderField(
            label: 'Translation Y',
            value: value.dy,
            min: -TransformSpec.maxOffset,
            max: TransformSpec.maxOffset,
            sliderKey: ValueKey('transform-dy-$label'),
            onChanged: (v) => change(value.copyWith(dy: v)),
          ),
        ),
        StylePair(
          StyleSliderField(
            label: 'Rotation',
            value: value.rotation,
            min: -180,
            max: 180,
            unit: ' °',
            sliderKey: ValueKey('transform-rotation-$label'),
            onChanged: (v) => change(value.copyWith(rotation: v)),
          ),
          StyleSliderField(
            label: 'Échelle',
            value: value.scale,
            min: TransformSpec.minScale,
            max: TransformSpec.maxScale,
            unit: ' ×',
            sliderKey: ValueKey('transform-scale-$label'),
            onChanged: (v) => change(value.copyWith(scale: v)),
          ),
        ),
      ],
    ];
  }
}
