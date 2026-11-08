/// Configuration persistée ([SuperSeparatorConfig]) d'un composant séparateur ou espaceur [SuperSeparator].
///
/// Supporte un mode trait de séparation (`divider`) ou espace vide (`spacer`),
/// une orientation horizontale ou verticale ([Axis]), un libellé optionnel
/// positionné (`start`, `center`, `end`), le style et l'épaisseur du trait,
/// les retraits (`indent`, `endIndent`), les liaisons JSON (`propertyBindings`)
/// et les surcharges d'états ([SeparatorConfigStates]).
library;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:material_ui/material_ui.dart';

import 'automatic_state.dart';
import 'component_config.dart';
import 'json_syntax.dart';
import 'json_text_binding.dart';

part 'super_separator_states.dart';

/// Nature du séparateur : trait visible (`divider`) ou espace vide (`spacer`).
enum SuperSeparatorKind {
  divider,
  spacer;

  bool get isDivider => this == SuperSeparatorKind.divider;
  bool get isSpacer => this == SuperSeparatorKind.spacer;
}

/// Style de tracé du trait d'un [SuperSeparator] (`solid`, `dashed`, `dotted`).
enum SuperSeparatorLineStyle { solid, dashed, dotted }

/// Position du libellé optionnel le long du trait d'un [SuperSeparator].
enum SuperSeparatorLabelPosition { start, center, end }

/// Propriétés d'un [SuperSeparator] pouvant être liées dynamiquement à un repository JSON.
enum SuperSeparatorProperty {
  label,
  extent,
  thickness,
  indent,
  endIndent,
  lineColor,
  color,
  fontFamily,
  fontSize,
  fontWeight,
  italic,
}

/// Modèle immuable de configuration persistée d'un composant [SuperSeparator].
@immutable
class SuperSeparatorConfig extends ComponentConfig {
  const SuperSeparatorConfig({
    this.kind = SuperSeparatorKind.divider,
    this.axis = Axis.horizontal,
    this.extent = 16,
    this.thickness = 1,
    this.indent = 0,
    this.endIndent = 0,
    this.lineStyle = SuperSeparatorLineStyle.solid,
    this.lineColor,
    this.label = '',
    this.labelPosition = SuperSeparatorLabelPosition.center,
    this.labelSpacing = 8,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.italic,
    this.color,
    this.letterSpacing,
    this.propertyBindings = const {},
    this.states,
  });

  final SuperSeparatorKind kind;
  final Axis axis;
  final double extent;
  final double thickness;
  final double indent;
  final double endIndent;
  final SuperSeparatorLineStyle lineStyle;
  final Color? lineColor;
  final String label;
  final SuperSeparatorLabelPosition labelPosition;
  final double labelSpacing;
  final String? fontFamily;
  final double? fontSize;
  final FontWeight? fontWeight;
  final bool? italic;
  final Color? color;
  final double? letterSpacing;
  final Map<SuperSeparatorProperty, JsonTextBinding> propertyBindings;
  final SeparatorConfigStates? states;

  @override
  String get componentType => 'separator';

  @override
  Iterable<JsonTextBinding> get referencedBindings =>
      JsonReader.collectReferencedBindings(
        propertyBindings,
        states,
        (c) => c.propertyBindings,
      );

  @override
  void validate() {
    _validateLeaf();
    states?._validateAgainst(this);
  }

  void _validateLeaf() {
    for (final binding in propertyBindings.values) {
      binding.validate();
    }
    if (!extent.isFinite ||
        extent < 0 ||
        !thickness.isFinite ||
        thickness <= 0 ||
        !indent.isFinite ||
        indent < 0 ||
        !endIndent.isFinite ||
        endIndent < 0 ||
        !labelSpacing.isFinite ||
        labelSpacing < 0 ||
        JsonReader.hasInvalidTypographyOrBox(
          fontFamily: fontFamily,
          fontSize: fontSize,
          letterSpacing: letterSpacing,
        )) {
      throw ArgumentError('Invalid Separator configuration.');
    }
  }

  SuperSeparatorConfig copyWith({
    SuperSeparatorKind? kind,
    Axis? axis,
    double? extent,
    double? thickness,
    double? indent,
    double? endIndent,
    SuperSeparatorLineStyle? lineStyle,
    Color? lineColor,
    String? label,
    SuperSeparatorLabelPosition? labelPosition,
    double? labelSpacing,
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    bool? italic,
    Color? color,
    double? letterSpacing,
    bool inheritLineColor = false,
    bool inheritFontFamily = false,
    bool inheritFontSize = false,
    bool inheritFontWeight = false,
    bool inheritItalic = false,
    bool inheritColor = false,
    bool inheritLetterSpacing = false,
    Map<SuperSeparatorProperty, JsonTextBinding>? propertyBindings,
    SeparatorConfigStates? states,
    bool clearStates = false,
  }) => SuperSeparatorConfig(
    kind: kind ?? this.kind,
    axis: axis ?? this.axis,
    extent: extent ?? this.extent,
    thickness: thickness ?? this.thickness,
    indent: indent ?? this.indent,
    endIndent: endIndent ?? this.endIndent,
    lineStyle: lineStyle ?? this.lineStyle,
    lineColor: inheritLineColor ? null : lineColor ?? this.lineColor,
    label: label ?? this.label,
    labelPosition: labelPosition ?? this.labelPosition,
    labelSpacing: labelSpacing ?? this.labelSpacing,
    fontFamily: inheritFontFamily ? null : fontFamily ?? this.fontFamily,
    fontSize: inheritFontSize ? null : fontSize ?? this.fontSize,
    fontWeight: inheritFontWeight ? null : fontWeight ?? this.fontWeight,
    italic: inheritItalic ? null : italic ?? this.italic,
    color: inheritColor ? null : color ?? this.color,
    letterSpacing: inheritLetterSpacing
        ? null
        : letterSpacing ?? this.letterSpacing,
    propertyBindings: propertyBindings ?? this.propertyBindings,
    states: clearStates ? null : states ?? this.states,
  );

  @override
  Map<String, Object?> toJson() {
    validate();
    return {
      'kind': kind.name,
      'axis': axis.name,
      'extent': extent,
      'thickness': thickness,
      'indent': indent,
      'endIndent': endIndent,
      'lineStyle': lineStyle.name,
      'lineColor': lineColor?.toARGB32(),
      'label': label,
      'labelPosition': labelPosition.name,
      'labelSpacing': labelSpacing,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'fontWeight': fontWeight?.value,
      'italic': italic,
      'color': color?.toARGB32(),
      'letterSpacing': letterSpacing,
      if (propertyBindings.isNotEmpty)
        'propertyBindings': JsonReader.encodePropertyBindings(propertyBindings),
      if (states != null) 'states': states!.toJson(),
    };
  }

  @override
  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperSeparatorConfig();
    return {
      if (kind != d.kind) 'kind': kind.name,
      if (axis != d.axis) 'axis': axis.name,
      if (extent != d.extent) 'extent': extent,
      if (thickness != d.thickness) 'thickness': thickness,
      if (indent != d.indent) 'indent': indent,
      if (endIndent != d.endIndent) 'endIndent': endIndent,
      if (lineStyle != d.lineStyle) 'lineStyle': lineStyle.name,
      if (lineColor != null) 'lineColor': JsonColor.toHex(lineColor!),
      if (label != d.label) 'label': label,
      if (labelPosition != d.labelPosition)
        'labelPosition': labelPosition.name,
      if (labelSpacing != d.labelSpacing) 'labelSpacing': labelSpacing,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': fontWeight!.value,
      if (italic != null) 'italic': italic,
      if (color != null) 'color': JsonColor.toHex(color!),
      if (letterSpacing != null) 'letterSpacing': letterSpacing,
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
  SuperSeparatorConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperSeparatorConfig.fromJson(patch, fallback: this);

  factory SuperSeparatorConfig.fromJson(
    Object? value, {
    SuperSeparatorConfig fallback = const SuperSeparatorConfig(),
  }) {
    if (value is! Map) {
      throw const FormatException('Invalid Separator configuration.');
    }
    const keys = {
      'kind',
      'axis',
      'orientation',
      'extent',
      'size',
      'thickness',
      'indent',
      'endIndent',
      'lineStyle',
      'lineColor',
      'label',
      'text',
      'labelPosition',
      'labelSpacing',
      'fontFamily',
      'fontSize',
      'fontWeight',
      'italic',
      'color',
      'letterSpacing',
      'propertyBindings',
      'states',
    };
    if (value.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown Separator preference.');
    }

    T field<T>(String key, T fallbackVal) =>
        JsonReader.field(value, key, fallbackVal, context: 'Separator');
    double? number(String key, double? fallbackVal) => JsonReader.nullableDouble(
      value,
      key,
      fallbackVal,
      context: 'Separator',
    );
    Color? colorField(String key, Color? fallbackVal) =>
        JsonReader.nullableColor(
          value,
          key,
          fallbackVal,
          errorMessage: 'Invalid Separator style.',
        );

    final kind = JsonReader.enumByName(
      SuperSeparatorKind.values,
      field('kind', fallback.kind.name),
      const {
        'line': SuperSeparatorKind.divider,
        'space': SuperSeparatorKind.spacer,
      },
    );
    final rawAxis = value.containsKey('axis')
        ? field('axis', fallback.axis.name)
        : value.containsKey('orientation')
        ? field('orientation', fallback.axis.name)
        : fallback.axis.name;
    final axis = JsonReader.enumByName(Axis.values, rawAxis);
    final lineStyle = JsonReader.enumByName(
      SuperSeparatorLineStyle.values,
      field('lineStyle', fallback.lineStyle.name),
    );
    final labelPosition = JsonReader.enumByName(
      SuperSeparatorLabelPosition.values,
      field('labelPosition', fallback.labelPosition.name),
      const {
        'left': SuperSeparatorLabelPosition.start,
        'top': SuperSeparatorLabelPosition.start,
        'right': SuperSeparatorLabelPosition.end,
        'bottom': SuperSeparatorLabelPosition.end,
      },
    );
    final fontWeight = JsonReader.readFontWeight(
      value,
      fallback.fontWeight,
      errorMessage: 'Invalid Separator style.',
    );
    final family = JsonReader.readFontFamily(
      value,
      fallback.fontFamily,
      errorMessage: 'Invalid Separator style.',
    );
    if (kind == null ||
        axis == null ||
        lineStyle == null ||
        labelPosition == null) {
      throw const FormatException('Invalid Separator style.');
    }

    final propertyBindings = JsonReader.readPropertyBindings(
      value,
      SuperSeparatorProperty.values,
      fallback.propertyBindings,
      context: 'Separator',
    );

    final resolvedLabel = JsonReader.readLabelOrText(
      value,
      fallback.label,
      context: 'Separator',
    );

    final resolvedExtent = value.containsKey('extent')
        ? (number('extent', fallback.extent) ?? fallback.extent)
        : value.containsKey('size')
        ? (number('size', fallback.extent) ?? fallback.extent)
        : fallback.extent;

    final result = SuperSeparatorConfig(
      kind: kind,
      axis: axis,
      extent: resolvedExtent,
      thickness: number('thickness', fallback.thickness) ?? fallback.thickness,
      indent: number('indent', fallback.indent) ?? fallback.indent,
      endIndent: number('endIndent', fallback.endIndent) ?? fallback.endIndent,
      lineStyle: lineStyle,
      lineColor: colorField('lineColor', fallback.lineColor),
      label: resolvedLabel,
      labelPosition: labelPosition,
      labelSpacing:
          number('labelSpacing', fallback.labelSpacing) ??
          fallback.labelSpacing,
      fontFamily: family,
      fontSize: number('fontSize', fallback.fontSize),
      fontWeight: fontWeight,
      italic: field<bool?>('italic', fallback.italic),
      color: colorField('color', fallback.color),
      letterSpacing: number('letterSpacing', fallback.letterSpacing),
      propertyBindings: propertyBindings,
      states: !value.containsKey('states')
          ? fallback.states
          : value['states'] == null
          ? null
          : SeparatorConfigStates.fromJson(value['states']),
    );
    try {
      result.validate();
    } on ArgumentError {
      throw const FormatException('Invalid Separator configuration.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperSeparatorConfig &&
      kind == other.kind &&
      axis == other.axis &&
      extent == other.extent &&
      thickness == other.thickness &&
      indent == other.indent &&
      endIndent == other.endIndent &&
      lineStyle == other.lineStyle &&
      lineColor == other.lineColor &&
      label == other.label &&
      labelPosition == other.labelPosition &&
      labelSpacing == other.labelSpacing &&
      fontFamily == other.fontFamily &&
      fontSize == other.fontSize &&
      fontWeight == other.fontWeight &&
      italic == other.italic &&
      color == other.color &&
      letterSpacing == other.letterSpacing &&
      mapEquals(propertyBindings, other.propertyBindings) &&
      states == other.states;

  @override
  int get hashCode => Object.hashAll([
    kind,
    axis,
    extent,
    thickness,
    indent,
    endIndent,
    lineStyle,
    lineColor,
    label,
    labelPosition,
    labelSpacing,
    fontFamily,
    fontSize,
    fontWeight,
    italic,
    color,
    letterSpacing,
    JsonReader.hashPropertyBindings(propertyBindings),
    states,
  ]);
}

/// Résumé des propriétés d'un [SuperSeparatorConfig] pour l'info-bulle du menu contextuel.
String formatSuperSeparatorTooltip({
  required String title,
  required SuperSeparatorConfig config,
}) {
  final kindLabel = config.kind == SuperSeparatorKind.spacer
      ? 'Espaceur (Spacer)'
      : 'Séparateur (Divider)';
  final axisLabel = config.axis == Axis.horizontal ? 'Horizontal' : 'Vertical';
  final details = <String>[
    'Espace : ${JsonReader.formatNumber(config.extent)} px',
    if (config.kind.isDivider) ...[
      'Épaisseur : ${JsonReader.formatNumber(config.thickness)} px',
      'Style : ${config.lineStyle.name}',
    ],
    if (config.indent > 0 || config.endIndent > 0)
      'Retraits : ${JsonReader.formatNumber(config.indent)} / ${JsonReader.formatNumber(config.endIndent)} px',
    if (config.label.trim().isNotEmpty) 'Libellé : ${config.label.trim()}',
    if (config.lineColor != null)
      'Couleur trait : ${JsonColor.toHex(config.lineColor!)}',
  ];
  return [
    title,
    '$kindLabel · $axisLabel',
    details.join(' · '),
  ].join('\n');
}
