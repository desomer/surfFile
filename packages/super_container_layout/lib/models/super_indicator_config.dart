 /// Configuration persistée ([SuperIndicatorConfig]) d'un composant indicateur / icône d'état [SuperIndicator].
///
/// Définit l'icône Material ([MaterialIconCatalog]), le libellé optionnel, la
/// typographie, le style de badge/surface, les liaisons JSON (`propertyBindings`)
/// et les surcharges d'états standards et personnalisés ([IndicatorConfigStates]).
library;

import 'package:flutter/foundation.dart' show mapEquals, setEquals;
import 'package:material_ui/material_ui.dart';

import '../theme/container_style.dart';
import 'automatic_state.dart';
import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'material_icon_catalog.dart';

part 'super_indicator_states.dart';

/// Position de l'icône par rapport au libellé optionnel dans un [SuperIndicator].
enum SuperIndicatorIconPosition { leading, trailing }

/// Propriétés d'un [SuperIndicator] pouvant être liées dynamiquement à un repository JSON.
enum SuperIndicatorProperty {
  icon,
  label,
  tooltip,
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

/// Catalogue d'icônes Material sérialisables par nom pour [SuperIndicatorConfig].
abstract final class SuperIndicatorIcons {
  static final Map<String, ({IconData icon, String label})> catalog = {
    for (final entry in MaterialIconCatalog.entries)
      entry.id: (icon: entry.icon, label: entry.label),
  };

  static bool isKnown(String name) => MaterialIconCatalog.isKnown(name);

  static IconData resolve(String name) => MaterialIconCatalog.resolve(name);

  static String labelOf(String name) => MaterialIconCatalog.labelOf(name);
}

/// Modèle immuable de configuration persistée d'un composant [SuperIndicator].
@immutable
class SuperIndicatorConfig extends ComponentConfig {
  const SuperIndicatorConfig({
    this.icon = 'info',
    this.iconPosition = SuperIndicatorIconPosition.leading,
    this.iconSize,
    this.iconSpacing = 6,
    this.label = '',
    this.tooltip = '',
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

  final String icon;
  final SuperIndicatorIconPosition iconPosition;
  final double? iconSize;
  final double iconSpacing;
  final String label;
  final String tooltip;
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
  final Map<SuperIndicatorProperty, JsonTextBinding> propertyBindings;
  final IndicatorConfigStates? states;

  @override
  String get componentType => 'indicator';

  @override
  Iterable<JsonTextBinding> get referencedBindings => [
    ?states?.binding,
    ...propertyBindings.values,
    for (final cfg in states?.named.values ?? const <SuperIndicatorConfig>[])
      ...cfg.propertyBindings.values,
    if (states?.hover case final h?) ...h.config.propertyBindings.values,
    if (states?.selected case final s?) ...s.config.propertyBindings.values,
    for (final auto
        in states?.automatic.values ?? const <IndicatorConfigOverride>[])
      ...auto.config.propertyBindings.values,
  ];

  @override
  void validate() {
    _validateLeaf();
    states?._validateAgainst(this);
  }

  void _validateLeaf() {
    for (final binding in propertyBindings.values) {
      binding.validate();
    }
    if ((icon.trim().isNotEmpty && !SuperIndicatorIcons.isKnown(icon)) ||
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
      throw ArgumentError('Invalid Indicator configuration.');
    }
  }

  SuperIndicatorConfig copyWith({
    String? icon,
    SuperIndicatorIconPosition? iconPosition,
    double? iconSize,
    double? iconSpacing,
    String? label,
    String? tooltip,
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
    Map<SuperIndicatorProperty, JsonTextBinding>? propertyBindings,
    IndicatorConfigStates? states,
    bool clearStates = false,
  }) => SuperIndicatorConfig(
    icon: icon ?? this.icon,
    iconPosition: iconPosition ?? this.iconPosition,
    iconSize: inheritIconSize ? null : iconSize ?? this.iconSize,
    iconSpacing: iconSpacing ?? this.iconSpacing,
    label: label ?? this.label,
    tooltip: tooltip ?? this.tooltip,
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
      'icon': icon,
      'iconPosition': iconPosition.name,
      'iconSize': iconSize,
      'iconSpacing': iconSpacing,
      'label': label,
      'tooltip': tooltip,
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
    const d = SuperIndicatorConfig();
    return {
      if (icon != d.icon) 'icon': icon,
      if (iconPosition != d.iconPosition) 'iconPosition': iconPosition.name,
      if (iconSize != null) 'iconSize': iconSize,
      if (iconSpacing != d.iconSpacing) 'iconSpacing': iconSpacing,
      if (label != d.label) 'label': label,
      if (tooltip.isNotEmpty) 'tooltip': tooltip,
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
  SuperIndicatorConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperIndicatorConfig.fromJson(patch, fallback: this);

  factory SuperIndicatorConfig.fromJson(
    Object? value, {
    SuperIndicatorConfig fallback = const SuperIndicatorConfig(),
  }) {
    if (value is! Map) {
      throw const FormatException('Invalid Indicator configuration.');
    }
    const keys = {
      'icon',
      'iconPosition',
      'iconSize',
      'iconSpacing',
      'label',
      'text',
      'tooltip',
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
      throw const FormatException('Unknown Indicator preference.');
    }

    T field<T>(String key, T fallbackVal) =>
        JsonReader.field(value, key, fallbackVal, context: 'Indicator');
    double? number(String key, double? fallbackVal) =>
        JsonReader.nullableDouble(
          value,
          key,
          fallbackVal,
          context: 'Indicator',
        );
    Color? colorField(String key, Color? fallbackVal) =>
        JsonReader.nullableColor(
          value,
          key,
          fallbackVal,
          errorMessage: 'Invalid Indicator style.',
        );

    final iconPosition = JsonReader.enumByName(
      SuperIndicatorIconPosition.values,
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
    if (iconPosition == null ||
        align == null ||
        (hasWeight && weight != null && fontWeight == null) ||
        (family != null && family is! String)) {
      throw const FormatException('Invalid Indicator style.');
    }

    final propertyBindings = JsonReader.readPropertyBindings(
      value,
      SuperIndicatorProperty.values,
      fallback.propertyBindings,
      context: 'Indicator',
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
      throw const FormatException('Invalid Indicator "style".');
    }

    final rawIcon = !value.containsKey('icon')
        ? fallback.icon
        : (value['icon'] ?? '');
    if (rawIcon is! String) {
      throw const FormatException('Invalid Indicator "icon".');
    }

    final result = SuperIndicatorConfig(
      icon: rawIcon,
      iconPosition: iconPosition,
      iconSize: number('iconSize', fallback.iconSize),
      iconSpacing: resolvedIconSpacing,
      label: resolvedLabel,
      tooltip: field('tooltip', fallback.tooltip),
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
          : IndicatorConfigStates.fromJson(value['states']),
    );
    try {
      result.validate();
    } on ArgumentError {
      throw const FormatException('Invalid Indicator configuration.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperIndicatorConfig &&
      icon == other.icon &&
      iconPosition == other.iconPosition &&
      iconSize == other.iconSize &&
      iconSpacing == other.iconSpacing &&
      label == other.label &&
      tooltip == other.tooltip &&
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
    icon,
    iconPosition,
    iconSize,
    iconSpacing,
    label,
    tooltip,
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

String _formatIndicatorNumber(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// Résumé des propriétés d'un [SuperIndicatorConfig] pour l'info-bulle du menu contextuel.
String formatSuperIndicatorTooltip({
  required String title,
  required SuperIndicatorConfig config,
}) {
  final contentParts = <String>[
    'Icône : ${config.icon.isEmpty ? 'Aucune' : config.icon}',
    if (config.label.isNotEmpty) 'Libellé : ${config.label}',
    if (config.tooltip.trim().isNotEmpty)
      'Infobulle : ${config.tooltip.trim()}',
  ];
  final styleParts = <String>[
    'Taille icône : ${config.iconSize != null ? '${_formatIndicatorNumber(config.iconSize!)} px' : 'Auto'}',
    if (config.label.isNotEmpty) ...[
      'Police : ${config.fontFamily ?? 'Auto'}',
      'Taille texte : ${config.fontSize != null ? '${_formatIndicatorNumber(config.fontSize!)} px' : 'Auto'}',
    ],
    if (config.radius != null)
      'Rayon : ${_formatIndicatorNumber(config.radius!)} px',
    if (config.elevation != null)
      'Élévation : ${_formatIndicatorNumber(config.elevation!)}',
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
    if (!config.enabled) 'Désactivé',
    if (contentParts.isNotEmpty) contentParts.join(' · '),
    styleParts.join(' · '),
  ].join('\n');
}
