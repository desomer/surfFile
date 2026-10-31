import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show mapEquals, setEquals;

import '../theme/container_style.dart';
import 'automatic_state.dart';
import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'material_icon_catalog.dart';

part 'super_action_states.dart';

enum SuperActionKind {
  text,
  icon,
  textAndIcon;

  bool get hasText => this != SuperActionKind.icon;
  bool get hasIcon => this != SuperActionKind.text;
}

enum SuperActionVariant {
  filled,
  tonal,
  elevated,
  outlined,
  text,
  icon,
  surface,
}

enum SuperActionIconPosition { leading, trailing }

enum SuperActionProperty {
  label,
  tooltip,
  icon,
  enabled,
  fontFamily,
  color,
  iconColor,
  backgroundColor,
  borderColor,
  fontSize,
  iconSize,
  fontWeight,
  italic,
  textAlign,
  radius,
  borderWidth,
  elevation,
}

/// Catalogue d'icônes Material sérialisables par nom pour [SuperActionConfig].
abstract final class SuperActionIcons {
  static final Map<String, ({IconData icon, String label})> catalog = {
    for (final entry in MaterialIconCatalog.entries)
      entry.id: (icon: entry.icon, label: entry.label),
  };

  static bool isKnown(String name) => MaterialIconCatalog.isKnown(name);

  static IconData resolve(String name) => MaterialIconCatalog.resolve(name);

  static String labelOf(String name) => MaterialIconCatalog.labelOf(name);
}

@immutable
class SuperActionConfig extends ComponentConfig {
  const SuperActionConfig({
    this.kind = SuperActionKind.text,
    this.variant = SuperActionVariant.filled,
    this.label = 'Action',
    this.tooltip = '',
    this.icon = 'touch_app',
    this.iconPosition = SuperActionIconPosition.leading,
    this.iconSize,
    this.iconSpacing = 8,
    this.enabled = true,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.italic,
    this.color,
    this.iconColor,
    this.backgroundColor,
    this.borderColor,
    this.radius,
    this.borderWidth,
    this.elevation,
    this.horizontalPadding,
    this.verticalPadding,
    this.textAlign = TextAlign.center,
    this.letterSpacing,
    this.style = const ContainerStyle(),
    this.propertyBindings = const {},
    this.states,
  });

  final SuperActionKind kind;
  final SuperActionVariant variant;
  final String label;
  final String tooltip;
  final String icon;
  final SuperActionIconPosition iconPosition;
  final double? iconSize;
  final double iconSpacing;
  final bool enabled;
  final String? fontFamily;
  final double? fontSize;
  final FontWeight? fontWeight;
  final bool? italic;
  final Color? color;
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? radius;
  final double? borderWidth;
  final double? elevation;
  final double? horizontalPadding;
  final double? verticalPadding;
  final TextAlign textAlign;
  final double? letterSpacing;
  final ContainerStyle style;
  final Map<SuperActionProperty, JsonTextBinding> propertyBindings;
  final ActionConfigStates? states;

  @override
  String get componentType => 'action';

  @override
  void validate() {
    _validateLeaf();
    states?._validateAgainst(this);
  }

  void _validateLeaf() {
    for (final binding in propertyBindings.values) {
      binding.validate();
    }
    if ((icon.trim().isNotEmpty && !SuperActionIcons.isKnown(icon)) ||
        !iconSpacing.isFinite ||
        iconSpacing < 0 ||
        (iconSize != null && (!iconSize!.isFinite || iconSize! <= 0)) ||
        (fontFamily != null && fontFamily!.trim().isEmpty) ||
        (fontSize != null && (!fontSize!.isFinite || fontSize! <= 0)) ||
        (letterSpacing != null && !letterSpacing!.isFinite) ||
        (radius != null && (!radius!.isFinite || radius! < 0)) ||
        (borderWidth != null && (!borderWidth!.isFinite || borderWidth! < 0)) ||
        (elevation != null && (!elevation!.isFinite || elevation! < 0)) ||
        (horizontalPadding != null &&
            (!horizontalPadding!.isFinite || horizontalPadding! < 0)) ||
        (verticalPadding != null &&
            (!verticalPadding!.isFinite || verticalPadding! < 0)) ||
        style.states != null) {
      throw ArgumentError('Invalid Action configuration.');
    }
  }

  SuperActionConfig copyWith({
    SuperActionKind? kind,
    SuperActionVariant? variant,
    String? label,
    String? tooltip,
    String? icon,
    SuperActionIconPosition? iconPosition,
    double? iconSize,
    double? iconSpacing,
    bool? enabled,
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    bool? italic,
    Color? color,
    Color? iconColor,
    Color? backgroundColor,
    Color? borderColor,
    double? radius,
    double? borderWidth,
    double? elevation,
    double? horizontalPadding,
    double? verticalPadding,
    TextAlign? textAlign,
    double? letterSpacing,
    ContainerStyle? style,
    bool inheritIconSize = false,
    bool inheritFontFamily = false,
    bool inheritFontSize = false,
    bool inheritFontWeight = false,
    bool inheritItalic = false,
    bool inheritColor = false,
    bool inheritIconColor = false,
    bool inheritBackgroundColor = false,
    bool inheritBorderColor = false,
    bool inheritRadius = false,
    bool inheritBorderWidth = false,
    bool inheritElevation = false,
    bool inheritHorizontalPadding = false,
    bool inheritVerticalPadding = false,
    bool inheritLetterSpacing = false,
    Map<SuperActionProperty, JsonTextBinding>? propertyBindings,
    ActionConfigStates? states,
    bool clearStates = false,
  }) => SuperActionConfig(
    kind: kind ?? this.kind,
    variant: variant ?? this.variant,
    label: label ?? this.label,
    tooltip: tooltip ?? this.tooltip,
    icon: icon ?? this.icon,
    iconPosition: iconPosition ?? this.iconPosition,
    iconSize: inheritIconSize ? null : iconSize ?? this.iconSize,
    iconSpacing: iconSpacing ?? this.iconSpacing,
    enabled: enabled ?? this.enabled,
    fontFamily: inheritFontFamily ? null : fontFamily ?? this.fontFamily,
    fontSize: inheritFontSize ? null : fontSize ?? this.fontSize,
    fontWeight: inheritFontWeight ? null : fontWeight ?? this.fontWeight,
    italic: inheritItalic ? null : italic ?? this.italic,
    color: inheritColor ? null : color ?? this.color,
    iconColor: inheritIconColor ? null : iconColor ?? this.iconColor,
    backgroundColor: inheritBackgroundColor
        ? null
        : backgroundColor ?? this.backgroundColor,
    borderColor: inheritBorderColor ? null : borderColor ?? this.borderColor,
    radius: inheritRadius ? null : radius ?? this.radius,
    borderWidth: inheritBorderWidth ? null : borderWidth ?? this.borderWidth,
    elevation: inheritElevation ? null : elevation ?? this.elevation,
    horizontalPadding: inheritHorizontalPadding
        ? null
        : horizontalPadding ?? this.horizontalPadding,
    verticalPadding: inheritVerticalPadding
        ? null
        : verticalPadding ?? this.verticalPadding,
    textAlign: textAlign ?? this.textAlign,
    letterSpacing: inheritLetterSpacing
        ? null
        : letterSpacing ?? this.letterSpacing,
    style: style ?? this.style,
    propertyBindings: propertyBindings ?? this.propertyBindings,
    states: clearStates ? null : states ?? this.states,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'kind': kind.name,
      'variant': variant.name,
      'label': label,
      'tooltip': tooltip,
      'icon': icon,
      'iconPosition': iconPosition.name,
      'iconSize': iconSize,
      'iconSpacing': iconSpacing,
      'enabled': enabled,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'fontWeight': fontWeight?.value,
      'italic': italic,
      'color': color?.toARGB32(),
      'iconColor': iconColor?.toARGB32(),
      'backgroundColor': backgroundColor?.toARGB32(),
      'borderColor': borderColor?.toARGB32(),
      'radius': radius,
      'borderWidth': borderWidth,
      'elevation': elevation,
      'horizontalPadding': horizontalPadding,
      'verticalPadding': verticalPadding,
      'textAlign': textAlign.name,
      'letterSpacing': letterSpacing,
      if (style != const ContainerStyle()) 'style': style.toJson(),
      if (propertyBindings.isNotEmpty)
        'propertyBindings': JsonReader.encodePropertyBindings(propertyBindings),
      if (states != null) 'states': states!.toJson(),
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperActionConfig();
    return {
      if (kind != d.kind) 'kind': kind.name,
      if (variant != d.variant) 'variant': variant.name,
      if (label != d.label) 'label': label,
      if (tooltip.isNotEmpty) 'tooltip': tooltip,
      if (icon != d.icon) 'icon': icon,
      if (iconPosition != d.iconPosition) 'iconPosition': iconPosition.name,
      if (iconSize != null) 'iconSize': iconSize,
      if (iconSpacing != d.iconSpacing) 'iconSpacing': iconSpacing,
      if (enabled != d.enabled) 'enabled': enabled,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': fontWeight!.value,
      if (italic != null) 'italic': italic,
      if (color != null) 'color': JsonColor.toHex(color!),
      if (iconColor != null) 'iconColor': JsonColor.toHex(iconColor!),
      if (backgroundColor != null)
        'backgroundColor': JsonColor.toHex(backgroundColor!),
      if (borderColor != null) 'borderColor': JsonColor.toHex(borderColor!),
      if (radius != null) 'radius': radius,
      if (borderWidth != null) 'borderWidth': borderWidth,
      if (elevation != null) 'elevation': elevation,
      if (horizontalPadding != null) 'horizontalPadding': horizontalPadding,
      if (verticalPadding != null) 'verticalPadding': verticalPadding,
      if (textAlign != d.textAlign) 'textAlign': textAlign.name,
      if (letterSpacing != null) 'letterSpacing': letterSpacing,
      if (style != const ContainerStyle()) 'style': style.toCompactJson(),
      if (propertyBindings.isNotEmpty)
        'propertyBindings': JsonReader.encodePropertyBindings(
          propertyBindings,
          compact: true,
        ),
      if (states != null) 'states': states!.toCompactJson(),
    };
  }

  /// Applique un patch JSON partiel sur cette configuration en conservant
  /// toutes les propriétés non mentionnées dans [patch].
  @override
  SuperActionConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperActionConfig.fromJson(patch, fallback: this);

  factory SuperActionConfig.fromJson(
    Object? value, {
    SuperActionConfig fallback = const SuperActionConfig(),
  }) {
    if (value is! Map) {
      throw const FormatException('Invalid Action configuration.');
    }
    const keys = {
      'kind',
      'variant',
      'label',
      'text',
      'tooltip',
      'icon',
      'iconPosition',
      'iconSize',
      'iconSpacing',
      'enabled',
      'fontFamily',
      'fontSize',
      'fontWeight',
      'italic',
      'color',
      'iconColor',
      'backgroundColor',
      'borderColor',
      'radius',
      'borderWidth',
      'elevation',
      'horizontalPadding',
      'verticalPadding',
      'textAlign',
      'letterSpacing',
      'style',
      'propertyBindings',
      'states',
    };
    if (value.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown Action preference.');
    }

    T field<T>(String key, T fallbackVal) =>
        JsonReader.field(value, key, fallbackVal, context: 'Action');
    double? number(String key, double? fallbackVal) =>
        JsonReader.nullableDouble(value, key, fallbackVal, context: 'Action');
    Color? colorField(String key, Color? fallbackVal) =>
        JsonReader.nullableColor(
          value,
          key,
          fallbackVal,
          errorMessage: 'Invalid Action style.',
        );

    final kind = JsonReader.enumByName(
      SuperActionKind.values,
      field('kind', fallback.kind.name),
      const {
        'both': SuperActionKind.textAndIcon,
        'text_icon': SuperActionKind.textAndIcon,
        'textIcon': SuperActionKind.textAndIcon,
      },
    );
    final variant = JsonReader.enumByName(
      SuperActionVariant.values,
      field('variant', fallback.variant.name),
    );
    final iconPosition = JsonReader.enumByName(
      SuperActionIconPosition.values,
      field('iconPosition', fallback.iconPosition.name),
    );
    final align = JsonReader.enumByName(
      TextAlign.values,
      field('textAlign', fallback.textAlign.name),
    );
    final hasWeight = value.containsKey('fontWeight');
    final weight = value['fontWeight'];
    final fontWeight = hasWeight
        ? JsonReader.parseFontWeight(weight)
        : fallback.fontWeight;
    final hasFamily = value.containsKey('fontFamily');
    final family = hasFamily ? value['fontFamily'] : fallback.fontFamily;
    if (kind == null ||
        variant == null ||
        iconPosition == null ||
        align == null ||
        (hasWeight && weight != null && fontWeight == null) ||
        (family != null && family is! String)) {
      throw const FormatException('Invalid Action style.');
    }

    final propertyBindings = JsonReader.readPropertyBindings(
      value,
      SuperActionProperty.values,
      fallback.propertyBindings,
      context: 'Action',
    );

    final resolvedLabel = value.containsKey('label')
        ? field('label', fallback.label)
        : value.containsKey('text')
        ? field('text', fallback.label)
        : fallback.label;

    final resolvedIconSpacing =
        number('iconSpacing', fallback.iconSpacing) ?? fallback.iconSpacing;

    final ContainerStyle resolvedStyle;
    if (!value.containsKey('style') || value['style'] == null) {
      resolvedStyle = value.containsKey('style')
          ? const ContainerStyle()
          : fallback.style;
    } else if (value['style'] is Map) {
      resolvedStyle = fallback.style.patchFromJson(value['style'] as Map);
    } else {
      throw const FormatException('Invalid Action "style".');
    }

    final rawIcon = !value.containsKey('icon')
        ? fallback.icon
        : (value['icon'] ?? '');
    if (rawIcon is! String) {
      throw const FormatException('Invalid Action "icon".');
    }

    final result = SuperActionConfig(
      kind: kind,
      variant: variant,
      label: resolvedLabel,
      tooltip: field('tooltip', fallback.tooltip),
      icon: rawIcon,
      iconPosition: iconPosition,
      iconSize: number('iconSize', fallback.iconSize),
      iconSpacing: resolvedIconSpacing,
      enabled: field('enabled', fallback.enabled),
      fontFamily: family as String?,
      fontSize: number('fontSize', fallback.fontSize),
      fontWeight: fontWeight,
      italic: field<bool?>('italic', fallback.italic),
      color: colorField('color', fallback.color),
      iconColor: colorField('iconColor', fallback.iconColor),
      backgroundColor: colorField('backgroundColor', fallback.backgroundColor),
      borderColor: colorField('borderColor', fallback.borderColor),
      radius: number('radius', fallback.radius),
      borderWidth: number('borderWidth', fallback.borderWidth),
      elevation: number('elevation', fallback.elevation),
      horizontalPadding: number(
        'horizontalPadding',
        fallback.horizontalPadding,
      ),
      verticalPadding: number('verticalPadding', fallback.verticalPadding),
      textAlign: align,
      letterSpacing: number('letterSpacing', fallback.letterSpacing),
      style: resolvedStyle,
      propertyBindings: propertyBindings,
      states: !value.containsKey('states')
          ? fallback.states
          : value['states'] == null
          ? null
          : ActionConfigStates.fromJson(value['states']),
    );
    try {
      result.validate();
    } on ArgumentError {
      throw const FormatException('Invalid Action configuration.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperActionConfig &&
      kind == other.kind &&
      variant == other.variant &&
      label == other.label &&
      tooltip == other.tooltip &&
      icon == other.icon &&
      iconPosition == other.iconPosition &&
      iconSize == other.iconSize &&
      iconSpacing == other.iconSpacing &&
      enabled == other.enabled &&
      fontFamily == other.fontFamily &&
      fontSize == other.fontSize &&
      fontWeight == other.fontWeight &&
      italic == other.italic &&
      color == other.color &&
      iconColor == other.iconColor &&
      backgroundColor == other.backgroundColor &&
      borderColor == other.borderColor &&
      radius == other.radius &&
      borderWidth == other.borderWidth &&
      elevation == other.elevation &&
      horizontalPadding == other.horizontalPadding &&
      verticalPadding == other.verticalPadding &&
      textAlign == other.textAlign &&
      letterSpacing == other.letterSpacing &&
      style == other.style &&
      mapEquals(propertyBindings, other.propertyBindings) &&
      states == other.states;

  @override
  int get hashCode => Object.hashAll([
    kind,
    variant,
    label,
    tooltip,
    icon,
    iconPosition,
    iconSize,
    iconSpacing,
    enabled,
    fontFamily,
    fontSize,
    fontWeight,
    italic,
    color,
    iconColor,
    backgroundColor,
    borderColor,
    radius,
    borderWidth,
    elevation,
    horizontalPadding,
    verticalPadding,
    textAlign,
    letterSpacing,
    style,
    Object.hashAllUnordered(
      propertyBindings.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    states,
  ]);
}

String _formatActionNumber(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// Résumé des propriétés d'un [SuperActionConfig] pour l'info-bulle du menu contextuel.
String formatSuperActionTooltip({
  required String title,
  required SuperActionConfig config,
}) {
  final kindLabel = switch (config.kind) {
    SuperActionKind.text => 'Texte',
    SuperActionKind.icon => 'Icône',
    SuperActionKind.textAndIcon => 'Texte et icône',
  };
  final variantLabel = switch (config.variant) {
    SuperActionVariant.filled => 'Plein',
    SuperActionVariant.tonal => 'Tonal',
    SuperActionVariant.elevated => 'Élevé',
    SuperActionVariant.outlined => 'Contour',
    SuperActionVariant.text => 'Texte',
    SuperActionVariant.icon => 'Icône',
    SuperActionVariant.surface => 'Surface',
  };
  final contentParts = <String>[
    if (config.kind.hasText)
      'Libellé : ${config.label.isEmpty ? 'Vide' : config.label}',
    if (config.kind.hasIcon) 'Icône : ${config.icon}',
    if (config.tooltip.trim().isNotEmpty)
      'Infobulle : ${config.tooltip.trim()}',
  ];
  final styleParts = <String>[
    'Police : ${config.fontFamily ?? 'Auto'}',
    'Taille : ${config.fontSize != null ? '${_formatActionNumber(config.fontSize!)} px' : 'Auto'}',
    if (config.radius != null)
      'Rayon : ${_formatActionNumber(config.radius!)} px',
    if (config.elevation != null)
      'Élévation : ${_formatActionNumber(config.elevation!)}',
    if (config.color != null) 'Couleur : ${JsonColor.toHex(config.color!)}',
    if (config.iconColor != null)
      'Couleur icône : ${JsonColor.toHex(config.iconColor!)}',
    if (config.backgroundColor != null)
      'Fond : ${JsonColor.toHex(config.backgroundColor!)}',
    if (config.borderColor != null)
      'Bordure : ${JsonColor.toHex(config.borderColor!)}',
  ];
  return [
    title,
    [
      'Type : $kindLabel',
      'Variante : $variantLabel',
      if (!config.enabled) 'Désactivé',
    ].join(' · '),
    if (contentParts.isNotEmpty) contentParts.join(' · '),
    styleParts.join(' · '),
  ].join('\n');
}

