import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/container_fill.dart';
import '../theme/design_system.dart';
import '../theme/interaction_effect.dart';
import '../theme/neon_style.dart';
import '../theme/appearance.dart';
import 'neon_surface.dart';
import '../theme/container_style.dart';
import 'style_editor_panel.dart';
import 'style_extras_controls.dart';
import 'styled_surface.dart';

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
    this.extraSections = const [],
    this.onResetColor,
    this.onReset,
    this.style,
    this.onStyle,
    this.extended = false,
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

  /// Mode panneau (non repliable) : sections supplémentaires, ajoutées après
  /// celles du style.
  final List<StyleEditorSection> extraSections;

  /// Mode panneau : remise de la couleur unie à sa valeur automatique.
  final VoidCallback? onResetColor;

  /// Mode panneau : remise à zéro du style.
  final VoidCallback? onReset;

  /// Mode panneau : style complet et son écriture, pour les réglages au-delà
  /// des paramètres ci-dessus.
  final ContainerStyle? style;
  final ValueChanged<ContainerStyle>? onStyle;

  /// Propose les réglages de forme et d'aspect étendus ([StyleExtrasControls]).
  final bool extended;

  bool get _panel => !collapsible;

  Widget _stack(List<Widget> children, {double gap = 8}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ],
  );

  List<Widget> _designSystemControls() => [
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
  ];

  List<Widget> _interactionControls() => [
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
  ];

  List<Widget> _hoverControls() => [
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
          dense: _panel,
        ),
    ],
  ];

  List<Widget> _fillControls() => [
    DropdownButtonFormField<FillType>(
      initialValue: value.type,
      isExpanded: true,
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
      _color('Couleur unie', solidColor, onSolidColorChanged!, dense: _panel),
    if (value.type != FillType.solid) ...[
      _color(
        'Couleur de départ',
        value.start,
        (color) => onChanged(value.copyWith(start: color)),
        dense: _panel,
      ),
      _color(
        'Couleur d’arrivée',
        value.end,
        (color) => onChanged(value.copyWith(end: color)),
        dense: _panel,
      ),
      if (value.type != FillType.radial)
        _slider(
          'Orientation (°)',
          value.angle,
          0,
          360,
          (angle) => onChanged(value.copyWith(angle: angle)),
          unit: '°',
        ),
      if (value.type == FillType.radial)
        _slider(
          'Rayon du dégradé',
          value.radius,
          .1,
          2,
          (radius) => onChanged(value.copyWith(radius: radius)),
          unit: '',
        ),
    ],
  ];

  List<Widget> _radiusControls() => [
    if (onRadiusChanged != null)
      _slider('Arrondi du conteneur', radius, 0, 36, onRadiusChanged!),
  ];

  List<Widget> _borderWidthControls() => [
    if (onBorderWidthChanged != null)
      _slider('Bordure du conteneur', borderWidth, 0, 4, onBorderWidthChanged!),
  ];

  List<Widget> _borderControls(
    BuildContext context, {
    bool resetButton = true,
  }) => [
    ..._borderWidthControls(),
    ..._borderColorControls(context, resetButton: resetButton),
  ];

  List<Widget> _borderColorControls(
    BuildContext context, {
    bool resetButton = true,
  }) => [
    if (onBorderColorChanged != null)
      _color(
        'Couleur de la bordure',
        borderColor ?? Theme.of(context).colorScheme.outlineVariant,
        onBorderColorChanged!,
        dense: _panel,
      ),
    if (onResetBorderColor != null && resetButton)
      TextButton(
        key: ValueKey('automatic-border-$label'),
        onPressed: onResetBorderColor,
        child: const Text('Couleur de bordure automatique'),
      ),
  ];

  List<Widget> _shadowControls() => [
    if (onElevationChanged != null)
      _slider('Élévation du conteneur', elevation, 0, 16, onElevationChanged!),
    if (onShadowOpacityChanged != null)
      _slider(
        'Opacité de l’ombre du conteneur',
        shadowOpacity,
        0,
        .6,
        onShadowOpacityChanged!,
        unit: '',
      ),
  ];

  List<Widget> _paddingControls() => [
    if (onPaddingChanged != null)
      _slider(
        'Marge intérieure (padding)',
        padding,
        0,
        48,
        onPaddingChanged!,
        key: ValueKey('padding-$label'),
      ),
  ];

  List<Widget> _marginControls() => [
    if (onMarginChanged != null)
      _slider(
        'Marge extérieure (margin)',
        margin,
        0,
        48,
        onMarginChanged!,
        key: ValueKey('margin-$label'),
      ),
  ];

  BoxDecoration _decoration(BuildContext context) => BoxDecoration(
    color: value.type == FillType.solid
        ? solidColor.withValues(alpha: solidColor.a * opacity)
        : null,
    gradient: value.gradient(opacity: opacity),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: borderColor ?? Theme.of(context).colorScheme.outlineVariant,
      width: borderWidth,
      style: borderWidth == 0 ? BorderStyle.none : BorderStyle.solid,
    ),
    boxShadow: elevation == 0
        ? null
        : designSystem == DesignSystem.neumorphism
        ? DesignSystem.neumorphicShadows(solidColor, elevation, shadowOpacity)
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: shadowOpacity),
              blurRadius: elevation * 2,
              offset: Offset(0, elevation / 2),
            ),
          ],
  );

  @override
  Widget build(BuildContext context) {
    if (_panel) return _buildPanel(context);
    final children = [
      if (onDesignSystemChanged != null) ...[
        ..._designSystemControls(),
        const SizedBox(height: 8),
      ],
      if (onInteractionEffectChanged != null) ..._interactionControls(),
      ..._hoverControls(),
      const SizedBox(height: 8),
      ..._fillControls(),
      ..._radiusControls(),
      ..._borderControls(context),
      ..._shadowControls(),
      ..._paddingControls(),
      ..._marginControls(),
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
            decoration: _decoration(context),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
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

  Widget _buildPanel(BuildContext context) {
    final interaction = [
      if (onInteractionEffectChanged != null) ..._interactionControls(),
      ..._hoverControls(),
    ];
    final fill = [
      ..._fillControls(),
      if (onResetColor != null)
        TextButton(
          key: ValueKey('automatic-$label'),
          onPressed: onResetColor,
          child: const Text('Couleur unie automatique'),
        ),
    ];
    final st = style;
    final onStyle = this.onStyle;
    final extras = extended && st != null && onStyle != null
        ? StyleExtrasControls(label: label, style: st, onStyle: onStyle)
        : null;
    final border = extras == null
        ? _borderControls(context)
        : [
            ...extras.border(
              _borderWidthControls(),
              hasWidth: onBorderWidthChanged != null,
            ),
            ..._borderColorControls(context),
          ];
    final sections = [
      if (onDesignSystemChanged != null)
        StyleEditorSection(
          id: 'design',
          title: 'Système de design',
          tag: 'designSystem',
          icon: Icons.palette_outlined,
          count: 1,
          child: _stack(_designSystemControls()),
        ),
      StyleEditorSection(
        id: 'fill',
        title: 'Fond & décoration',
        tag: 'decoration',
        icon: Icons.format_color_fill,
        count: 2,
        child: _stack(fill),
      ),
      if (onRadiusChanged != null)
        StyleEditorSection(
          id: 'radius',
          title: 'Rayon de bordure',
          tag: 'borderRadius',
          icon: Icons.rounded_corner,
          count: 1,
          half: true,
          child: _stack(
            extras == null
                ? _radiusControls()
                : extras.radius(_radiusControls()),
          ),
        ),
      if (border.isNotEmpty)
        StyleEditorSection(
          id: 'border',
          title: 'Bordure',
          tag: 'border',
          icon: Icons.border_style,
          count: 2,
          half: true,
          child: _stack(border),
        ),
      if (onElevationChanged != null || onShadowOpacityChanged != null)
        StyleEditorSection(
          id: 'shadow',
          title: 'Ombre portée',
          tag: 'boxShadow',
          icon: Icons.layers_outlined,
          count: 2,
          child: _stack(
            extras == null
                ? _shadowControls()
                : extras.dropShadow(_shadowControls()),
          ),
        ),
      if (extras != null)
        StyleEditorSection(
          id: 'inner',
          title: 'Ombre intérieure',
          tag: 'innerShadow',
          icon: Icons.brightness_low,
          count: 1,
          child: _stack(extras.innerShadow()),
        ),
      if (onMarginChanged != null)
        StyleEditorSection(
          id: 'margin',
          title: 'Marge extérieure',
          tag: 'margin',
          icon: Icons.crop_free,
          count: 1,
          half: true,
          child: _stack(
            extras == null
                ? _marginControls()
                : extras.spacing(_marginControls(), padding: false),
          ),
        ),
      if (onPaddingChanged != null)
        StyleEditorSection(
          id: 'padding',
          title: 'Marge intérieure',
          tag: 'padding',
          icon: Icons.padding,
          count: 1,
          half: true,
          child: _stack(
            extras == null
                ? _paddingControls()
                : extras.spacing(_paddingControls(), padding: true),
          ),
        ),
      if (extras != null) ...[
        StyleEditorSection(
          id: 'opacity',
          title: 'Opacité & flou',
          tag: 'opacity',
          icon: Icons.opacity,
          count: 2,
          child: _stack(extras.opacityAndBlur()),
        ),
        StyleEditorSection(
          id: 'pattern',
          title: 'Motif',
          tag: 'pattern',
          icon: Icons.grain,
          count: 2,
          child: _stack(extras.pattern()),
        ),
        StyleEditorSection(
          id: 'transform',
          title: 'Transformation',
          tag: 'transform',
          icon: Icons.open_with,
          count: 4,
          child: _stack(extras.transform()),
        ),
      ],
      if (interaction.isNotEmpty)
        StyleEditorSection(
          id: 'interaction',
          title: 'Interaction',
          tag: 'InteractionEffect',
          icon: Icons.touch_app_outlined,
          count: 3,
          child: _stack(interaction),
        ),
      if (onNeonChanged != null)
        StyleEditorSection(
          id: 'neon',
          title: 'Effet néon',
          tag: 'NeonStyle',
          icon: Icons.flare,
          count: 3,
          child: NeonStyleEditor(
            label: label,
            value: neon,
            accent: accent,
            onChanged: onNeonChanged!,
          ),
        ),
      ...extraSections,
    ];
    return StyleEditorPanel(
      sections: sections,
      preview: _PreviewPane(editor: this),
      onReset: onReset,
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    Key? key,
    String unit = ' dp',
  }) {
    if (!_panel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label : ${value.toStringAsFixed(1)}'),
          Slider(
            key: key,
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      );
    }
    return StyleSliderField(
      label: label,
      value: value,
      min: min,
      max: max,
      unit: unit,
      sliderKey: key,
      onChanged: onChanged,
    );
  }
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

Widget _color(
  String label,
  Color color,
  ValueChanged<Color> onChanged, {
  bool dense = false,
}) => styleColorTile(label, color, onChanged, dense: dense);

/// Ligne repliable avec pastille et sélecteur de couleur (palette, roue).
Widget styleColorTile(
  String label,
  Color color,
  ValueChanged<Color> onChanged, {
  Key? key,
  bool dense = false,
}) => ExpansionTile(
  key: key,
  title: Text(label, style: dense ? const TextStyle(fontSize: 13) : null),
  dense: dense,
  tilePadding: dense ? EdgeInsets.zero : null,
  childrenPadding: dense ? const EdgeInsets.only(bottom: 8) : null,
  leading: CircleAvatar(backgroundColor: color, radius: dense ? 10 : 12),
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

/// Prévisualisation du panneau : la surface éditée, avec en option les zones
/// de marge extérieure et intérieure.
class _PreviewPane extends StatefulWidget {
  const _PreviewPane({required this.editor});

  final ContainerStyleEditor editor;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  bool _spacing = false;

  static String _dp(double v) => v.round().toString();

  static String _ins(EdgeInsets i) =>
      i.left == i.top && i.top == i.right && i.right == i.bottom
      ? _dp(i.left)
      : '${_dp(i.top)}/${_dp(i.right)}/${_dp(i.bottom)}/${_dp(i.left)}';

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final spacing = _spacing;
    final textColor = Appearance.foreground(
      editor.value.type == FillType.solid
          ? editor.solidColor
          : editor.value.start,
    );
    final guide = scheme.primary.withValues(alpha: .7);
    final st = editor.style;
    final padding = st?.contentPadding ?? EdgeInsets.all(editor.padding);
    final margin = st?.outerMargin ?? EdgeInsets.all(editor.margin);
    final label = Text('Aper\u00e7u', style: TextStyle(color: textColor));
    final zone = spacing
        ? CustomPaint(
            foregroundPainter: _DashedRectPainter(guide, radius: 4),
            child: SizedBox.expand(child: Center(child: label)),
          )
        : label;
    final height = spacing ? padding.vertical + 64 : 110.0;
    final key = ValueKey('preview-${editor.label}');
    Widget surface = st == null
        ? Container(
            key: key,
            height: height,
            width: double.infinity,
            padding: spacing ? padding : null,
            decoration: editor._decoration(context),
            child: Center(child: zone),
          )
        : SizedBox(
            key: key,
            height: height,
            width: double.infinity,
            child: StyledSurface(
              style: st,
              fallbackColor: editor.solidColor,
              borderColor:
                  editor.borderColor ??
                  Theme.of(context).colorScheme.outlineVariant,
              child: Padding(
                padding: spacing ? padding : EdgeInsets.zero,
                child: Center(child: zone),
              ),
            ),
          );
    surface = Padding(
      padding: editor.neon.enabled ? const EdgeInsets.all(18) : EdgeInsets.zero,
      child: st != null
          ? surface
          : NeonSurface(
              style: editor.neon,
              accent: editor.accent,
              radius: editor.radius,
              child: surface,
            ),
    );
    if (spacing) {
      surface = CustomPaint(
        foregroundPainter: _DashedRectPainter(muted.withValues(alpha: .7)),
        child: Container(
          color: muted.withValues(alpha: .08),
          padding: margin,
          child: surface,
        ),
      );
    }
    return Material(
      key: const ValueKey('style-preview'),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Prévisualisation',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Rendu Flutter',
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    color: muted.withValues(alpha: .7),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('preview-spacing'),
                onPressed: () => setState(() => _spacing = !_spacing),
                icon: Icon(
                  _spacing ? Icons.visibility_off_outlined : Icons.crop_free,
                  size: 15,
                ),
                label: Text(
                  _spacing
                      ? 'Masquer les espacements'
                      : 'Afficher les espacements',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
          Container(
            color: scheme.surfaceContainerHighest.withValues(alpha: .35),
            padding: const EdgeInsets.all(16),
            child: surface,
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: muted,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'margin ${_ins(margin)} \u00b7 padding ${_ins(padding)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'radius ${st?.radii == null ? _dp(editor.radius) : st!.radii!.values.map(_dp).join('\u00b7')}',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter(this.color, {this.radius = 0});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
