import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/json_text_binding.dart';
import '../../../services/repositories/json_list_scope.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../history/editor_history.dart';
import '../repositories/repository_binding_fields.dart';

import '../../../theme/container_fill.dart';
import '../../../theme/design_system.dart';
import '../../../theme/interaction_effect.dart';
import '../../../theme/neon_style.dart';
import '../../../theme/appearance.dart';
import '../../surfaces/neon_surface.dart';
import '../../../theme/container_style.dart';
import 'style_editor_panel.dart';
import 'style_extras_controls.dart';
import '../../surfaces/styled_surface.dart';

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
    this.onResetHoverColor,
    this.extraSections = const [],
    this.onResetColor,
    this.onReset,
    this.style,
    this.onStyle,
    this.extended = false,
    this.dense,
    this.onDenseChanged,
    this.onLabelChanged,
    this.ownerContext,
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
  final VoidCallback? onResetHoverColor;

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

  /// Mode panneau compact ; si absent, reprend le mode mémorisé de la session.
  final bool? dense;
  final ValueChanged<bool>? onDenseChanged;
  final ValueChanged<String>? onLabelChanged;
  final BuildContext? ownerContext;

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

  Widget _fieldLabel(String title, {String? helper}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      if (helper != null)
        Text(
          helper,
          style: const TextStyle(fontSize: 11),
        ),
    ],
  );

  static const _compactSegmentStyle = ButtonStyle(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  static IconData _designSystemIcon(DesignSystem system) => switch (system) {
    DesignSystem.material => Icons.layers_outlined,
    DesignSystem.neumorphism => Icons.wb_twilight,
    DesignSystem.liquidGlass => Icons.blur_on,
  };

  static IconData _interactionEffectIcon(InteractionEffect effect) =>
      switch (effect) {
        InteractionEffect.ripple => Icons.touch_app_outlined,
        InteractionEffect.pressed => Icons.compress,
        InteractionEffect.elevation => Icons.trending_up,
      };

  static IconData _hoverTintIcon(HoverTint tint) => switch (tint) {
    HoverTint.material => Icons.tonality,
    HoverTint.accent => Icons.color_lens_outlined,
    HoverTint.custom => Icons.palette_outlined,
  };

  List<Widget> _designSystemControls() => [
    _fieldLabel(
      'Système de design',
      helper: 'Règle l’arrondi, la bordure, l’ombre et le fond.',
    ),
    SegmentedButton<DesignSystem>(
      key: ValueKey('design-system-$label'),
      showSelectedIcon: false,
      style: _compactSegmentStyle,
      segments: [
        for (final system in DesignSystem.values)
          ButtonSegment<DesignSystem>(
            value: system,
            tooltip: system.label,
            icon: Flexible(
              flex: 0,
              child: Icon(_designSystemIcon(system), size: 14),
            ),
            label: Text(system.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      selected: {designSystem},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) onDesignSystemChanged!(selected.first);
      },
    ),
  ];

  List<Widget> _interactionControls() => [
    _fieldLabel(
      'Effet d’interaction',
      helper: interactionEffect.description,
    ),
    SegmentedButton<InteractionEffect>(
      key: ValueKey('interaction-effect-$label'),
      showSelectedIcon: false,
      style: _compactSegmentStyle,
      segments: [
        for (final effect in InteractionEffect.values)
          ButtonSegment<InteractionEffect>(
            value: effect,
            tooltip: effect.label,
            icon: Flexible(
              flex: 0,
              child: Icon(_interactionEffectIcon(effect), size: 14),
            ),
            label: Text(effect.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      selected: {interactionEffect},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) onInteractionEffectChanged!(selected.first);
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
      _fieldLabel('Couleur du survol'),
      SegmentedButton<HoverTint>(
        key: ValueKey('hover-tint-$label'),
        showSelectedIcon: false,
        style: _compactSegmentStyle,
        segments: [
          for (final tint in HoverTint.values)
            ButtonSegment<HoverTint>(
              value: tint,
              tooltip: tint.label,
              icon: Flexible(
                flex: 0,
                child: Icon(_hoverTintIcon(tint), size: 14),
              ),
              label: Text(tint.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        selected: {hoverTint},
        onSelectionChanged: (selected) {
          if (selected.isNotEmpty) onHoverTintChanged!(selected.first);
        },
      ),
      if (hoverTint == HoverTint.custom && onHoverColorChanged != null)
        _color(
          'Couleur du voile',
          hoverColor ?? accent,
          onHoverColorChanged!,
          key: ValueKey('hover-color-$label'),
          dense: _panel,
          onClear:
              onResetHoverColor ??
              (style != null && onStyle != null
                  ? () => onStyle!(style!.copyWith(resetHoverColor: true))
                  : null),
        ),
    ],
  ];

  List<Widget> _fillControls() => [
    _fieldLabel('Type de fond'),
    SegmentedButton<FillType>(
      key: ValueKey('fill-type-$label'),
      showSelectedIcon: false,
      style: _compactSegmentStyle,
      segments: const [
        ButtonSegment(
          value: FillType.solid,
          tooltip: 'Couleur unie',
          icon: Flexible(
            flex: 0,
            child: Icon(Icons.format_color_fill, size: 14),
          ),
          label: Text('Couleur unie', overflow: TextOverflow.ellipsis),
        ),
        ButtonSegment(
          value: FillType.linear,
          tooltip: 'Linéaire',
          icon: Flexible(flex: 0, child: Icon(Icons.gradient, size: 14)),
          label: Text('Linéaire', overflow: TextOverflow.ellipsis),
        ),
        ButtonSegment(
          value: FillType.radial,
          tooltip: 'Radial',
          icon: Flexible(flex: 0, child: Icon(Icons.lens_blur, size: 14)),
          label: Text('Radial', overflow: TextOverflow.ellipsis),
        ),
        ButtonSegment(
          value: FillType.sweep,
          tooltip: 'Circulaire',
          icon: Flexible(flex: 0, child: Icon(Icons.track_changes, size: 14)),
          label: Text('Circulaire', overflow: TextOverflow.ellipsis),
        ),
      ],
      selected: {value.type},
      onSelectionChanged: (selected) {
        if (selected.isNotEmpty) {
          onChanged(value.copyWith(type: selected.first));
        }
      },
    ),
    if (value.type == FillType.solid && onSolidColorChanged != null)
      _color(
        'Couleur unie',
        solidColor,
        onSolidColorChanged!,
        key: ValueKey('solid-color-$label'),
        dense: _panel,
        onClear:
            onResetColor ??
            (style != null && onStyle != null
                ? () => onStyle!(style!.copyWith(resetColor: true))
                : null),
      ),
    if (value.type != FillType.solid) ...[
      _color(
        'Couleur de départ',
        value.start,
        (color) => onChanged(value.copyWith(start: color)),
        key: ValueKey('start-color-$label'),
        dense: _panel,
        onClear: () => onChanged(value.copyWith(resetStart: true)),
      ),
      _color(
        'Couleur d’arrivée',
        value.end,
        (color) => onChanged(value.copyWith(end: color)),
        key: ValueKey('end-color-$label'),
        dense: _panel,
        onClear: () => onChanged(value.copyWith(resetEnd: true)),
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
    _BackgroundImageUrlField(
      key: ValueKey('image-url-$label'),
      fieldKey: ValueKey('image-url-field-$label'),
      clearKey: ValueKey('image-url-clear-$label'),
      bindKey: ValueKey('image-url-bind-$label'),
      bindingKeyPrefix: 'image-url-binding-$label',
      ownerContext: ownerContext,
      value: value.imageUrl,
      binding: style?.imageBinding ?? value.imageBinding,
      onChanged: (url) => onChanged(value.copyWith(imageUrl: url)),
      onBindingChanged: (binding) {
        if (style != null && onStyle != null) {
          final bindings =
              Map<ContainerStyleProperty, JsonTextBinding>.of(
                style!.propertyBindings,
              );
          if (binding == null) {
            bindings.remove(ContainerStyleProperty.imageUrl);
          } else {
            bindings[ContainerStyleProperty.imageUrl] = binding;
          }
          onStyle!(
            style!.copyWith(
              propertyBindings: bindings,
              fill: style!.fill.imageBinding == null
                  ? style!.fill
                  : style!.fill.copyWith(clearImageBinding: true),
            ),
          );
        } else {
          onChanged(
            value.copyWith(
              imageBinding: binding,
              clearImageBinding: binding == null,
            ),
          );
        }
      },
    ),
    if (value.hasImage || style?.hasImage == true) ...[
      DropdownButtonFormField<BoxFit>(
        key: ValueKey('image-fit-$label-${value.imageFit.name}'),
        initialValue: value.imageFit,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Ajustement de l’image'),
        items: const [
          DropdownMenuItem(
            value: BoxFit.cover,
            child: Text('Remplir (Cover)'),
          ),
          DropdownMenuItem(
            value: BoxFit.contain,
            child: Text('Contenir (Contain)'),
          ),
          DropdownMenuItem(
            value: BoxFit.fill,
            child: Text('Étirer (Fill)'),
          ),
          DropdownMenuItem(
            value: BoxFit.fitWidth,
            child: Text('Ajuster à la largeur'),
          ),
          DropdownMenuItem(
            value: BoxFit.fitHeight,
            child: Text('Ajuster à la hauteur'),
          ),
          DropdownMenuItem(
            value: BoxFit.none,
            child: Text('Taille originale'),
          ),
          DropdownMenuItem(
            value: BoxFit.scaleDown,
            child: Text('Réduire si nécessaire'),
          ),
        ],
        onChanged: (fit) {
          if (fit != null) onChanged(value.copyWith(imageFit: fit));
        },
      ),
      _slider(
        'Opacité de l’image',
        value.imageOpacity,
        0,
        1,
        (imageOpacity) => onChanged(value.copyWith(imageOpacity: imageOpacity)),
        key: ValueKey('image-opacity-$label'),
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
        key: ValueKey('border-color-$label'),
        dense: _panel,
        onClear:
            onResetBorderColor ??
            (style != null && onStyle != null
                ? () => onStyle!(style!.copyWith(resetBorderColor: true))
                : null),
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
        1,
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

  BoxDecoration _decoration(BuildContext context, [ContainerFill? resolved]) {
    final fill = resolved ?? value;
    return BoxDecoration(
      color: fill.type == FillType.solid
          ? solidColor.withValues(alpha: solidColor.a * opacity)
          : null,
      gradient: fill.gradient(opacity: opacity),
      image: fill.decorationImage(opacity: opacity),
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
  }

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
          child: BoundContainerFill(
            fill: value,
            builder: (context, fill) => Container(
              key: ValueKey('preview-$label'),
              height: 100,
              width: double.infinity,
              decoration: _decoration(context, fill),
            ),
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
      ...extraSections,
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
      if (onMarginChanged != null)
        StyleEditorSection(
          id: 'margin',
          title: 'Marge extérieure',
          tag: 'margin',
          icon: Icons.crop_free,
          count: 1,
          half: true,
          child: _stack(
            extras == null ? _marginControls() : extras.spacing(padding: false),
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
            extras == null ? _paddingControls() : extras.spacing(padding: true),
          ),
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
      if (extras != null) ...[
        StyleEditorSection(
          id: 'inner',
          title: 'Ombre intérieure',
          tag: 'innerShadow',
          icon: Icons.brightness_low,
          count: 1,
          child: _stack(extras.innerShadow()),
        ),
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
    ];
    return StyleEditorPanel(
      sections: sections,
      preview: _PreviewPane(editor: this),
      dense: dense,
      onDenseChanged: onDenseChanged,
      label: label,
      onLabelChanged: onLabelChanged,
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
          EditorHistorySlider(
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
          key: ValueKey('neon-color-$label'),
          onClear: () => onChanged(value.copyWith(resetColor: true)),
        ),
        TextButton(
          onPressed: () => onChanged(value.copyWith(resetColor: true)),
          child: const Text('Utiliser la couleur d’accent'),
        ),
        Text('Intensité : ${(value.intensity * 100).round()} %'),
        EditorHistorySlider(
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
  Key? key,
  bool dense = false,
  VoidCallback? onClear,
}) => styleColorTile(
  label,
  color,
  onChanged,
  key: key,
  dense: dense,
  onClear: onClear,
);

/// Ligne repliable avec pastille et sélecteur de couleur (palette, roue).
Widget styleColorTile(
  String label,
  Color color,
  ValueChanged<Color> onChanged, {
  Key? key,
  bool dense = false,
  VoidCallback? onClear,
}) => ExpansionTile(
  key: key,
  title: onClear == null
      ? Text(label, style: dense ? const TextStyle(fontSize: 13) : null)
      : Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: dense ? const TextStyle(fontSize: 13) : null,
              ),
            ),
            IconButton(
              key: key is ValueKey
                  ? ValueKey('${key.value}-clear')
                  : ValueKey('clear-color-$label'),
              tooltip: 'Retirer la couleur',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
              ),
              iconSize: 16,
              onPressed: onClear,
              icon: const Icon(Icons.format_color_reset_outlined),
            ),
          ],
        ),
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
        ? BoundContainerFill(
            fill: editor.value,
            builder: (context, fill) => Container(
              key: key,
              height: height,
              width: double.infinity,
              padding: spacing ? padding : null,
              decoration: editor._decoration(context, fill),
              child: Center(child: zone),
            ),
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
    final ownerCtx = editor.ownerContext;
    if (ownerCtx != null && ownerCtx.mounted) {
      final ownerListScope = JsonListScope.maybeOf(ownerCtx);
      if (ownerListScope != null && JsonListScope.maybeOf(context) == null) {
        surface = JsonListScope(
          repositoryId: ownerListScope.repositoryId,
          indices: ownerListScope.indices,
          placeholder: ownerListScope.placeholder,
          selected: ownerListScope.selected,
          child: surface,
        );
      }
      final ownerStore = JsonRepositoryScope.maybeOf(ownerCtx);
      if (ownerStore != null && JsonRepositoryScope.maybeOf(context) == null) {
        surface = JsonRepositoryScope(store: ownerStore, child: surface);
      }
    }
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

class _BackgroundImageUrlField extends StatefulWidget {
  const _BackgroundImageUrlField({
    required this.value,
    required this.onChanged,
    this.binding,
    this.onBindingChanged,
    this.ownerContext,
    this.fieldKey,
    this.clearKey,
    this.bindKey,
    this.bindingKeyPrefix,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final JsonTextBinding? binding;
  final ValueChanged<JsonTextBinding?>? onBindingChanged;
  final BuildContext? ownerContext;
  final Key? fieldKey;
  final Key? clearKey;
  final Key? bindKey;
  final String? bindingKeyPrefix;

  @override
  State<_BackgroundImageUrlField> createState() =>
      _BackgroundImageUrlFieldState();
}

class _BackgroundImageUrlFieldState extends State<_BackgroundImageUrlField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_BackgroundImageUrlField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      key: widget.fieldKey,
      controller: _controller,
      keyboardType: TextInputType.url,
      decoration: InputDecoration(
        labelText: 'Image de fond (URL)',
        hintText: 'https://...',
        helperText: widget.binding == null
            ? null
            : 'Lié à : ${widget.binding!.toCompactJson()}',
        suffixIcon: widget.value.isEmpty
            ? null
            : IconButton(
                key: widget.clearKey,
                tooltip: 'Effacer l’image',
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              ),
      ),
      onChanged: widget.onChanged,
    );
    if (widget.onBindingChanged == null) return field;
    final targetContext =
        widget.ownerContext != null && widget.ownerContext!.mounted
        ? widget.ownerContext!
        : context;
    final repositories =
        JsonRepositoryScope.maybeOf(targetContext) ??
        JsonRepositoryScope.maybeOf(context);
    final listScope =
        JsonListScope.maybeOf(targetContext) ??
        JsonListScope.maybeOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: field),
        IconButton(
          key: widget.bindKey,
          tooltip: widget.binding != null
              ? 'Modifier la liaison de l’image de fond'
              : 'Lier l’image de fond à un repository',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            widget.binding != null ? Icons.link : Icons.add_link,
            size: 18,
          ),
          onPressed: repositories == null
              ? null
              : () async {
                  final result = await showRepositoryBindingDialog(
                    context: targetContext,
                    title: 'Lier l’image de fond',
                    keyPrefix: widget.bindingKeyPrefix ?? 'image-url-binding',
                    pathHint: 'client.imageUrl',
                    binding: widget.binding,
                    store: repositories,
                    listScope: listScope,
                    helper:
                        'Lecture seule : la valeur du repository remplace ce paramètre.',
                  );
                  if (result != null && mounted) {
                    widget.onBindingChanged!(result.binding);
                  }
                },
        ),
      ],
    );
  }
}

