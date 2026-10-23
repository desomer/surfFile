import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;

import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'automatic_state.dart';
import 'super_text_field_config.dart';

part 'super_value_states.dart';

enum SuperValueMode { display, input }

enum SuperValueKind {
  text,
  checkbox,
  switchControl;

  bool get isBoolean => this != SuperValueKind.text;
}

enum SuperValueProperty {
  label,
  placeholder,
  fontFamily,
  color,
  fontSize,
  fontWeight,
  italic,
  textAlign,
}

@immutable
class SuperValueConfig {
  const SuperValueConfig({
    this.mode = SuperValueMode.display,
    this.kind = SuperValueKind.text,
    this.initialText = '',
    this.initialBool = false,
    this.label = '',
    this.placeholder = '',
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.italic,
    this.color,
    this.textAlign = TextAlign.start,
    this.lineHeight,
    this.letterSpacing,
    this.binding,
    this.propertyBindings = const {},
    this.field = const SuperTextFieldConfig(),
    this.states,
  });

  final SuperValueMode mode;
  final SuperValueKind kind;
  final String initialText;
  final bool initialBool;
  final String label;
  final String placeholder;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final int minLines;
  final int maxLines;
  final String? fontFamily;
  final double? fontSize;
  final FontWeight? fontWeight;
  final bool? italic;
  final Color? color;
  final TextAlign textAlign;
  final double? lineHeight;
  final double? letterSpacing;
  final JsonTextBinding? binding;
  final Map<SuperValueProperty, JsonTextBinding> propertyBindings;
  final SuperTextFieldConfig field;
  final ValueConfigStates? states;

  void validate() {
    _validateLeaf();
    states?._validateAgainst(this);
  }

  void _validateLeaf() {
    binding?.validate();
    for (final binding in propertyBindings.values) {
      binding.validate();
    }
    field.validateFor(obscureText: obscureText, maxLines: maxLines);
    if (minLines < 1 ||
        maxLines < minLines ||
        (obscureText &&
            (kind.isBoolean ||
                initialText.isNotEmpty ||
                minLines != 1 ||
                maxLines != 1)) ||
        (fontFamily != null && fontFamily!.trim().isEmpty) ||
        (fontSize != null && (!fontSize!.isFinite || fontSize! <= 0)) ||
        (lineHeight != null && (!lineHeight!.isFinite || lineHeight! <= 0)) ||
        (letterSpacing != null && !letterSpacing!.isFinite)) {
      throw ArgumentError('Invalid Value configuration.');
    }
  }

  SuperValueConfig copyWith({
    SuperValueMode? mode,
    SuperValueKind? kind,
    String? initialText,
    bool? initialBool,
    String? label,
    String? placeholder,
    bool? enabled,
    bool? readOnly,
    bool? obscureText,
    int? minLines,
    int? maxLines,
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    bool? italic,
    Color? color,
    TextAlign? textAlign,
    double? lineHeight,
    double? letterSpacing,
    bool inheritFontFamily = false,
    bool inheritFontSize = false,
    bool inheritFontWeight = false,
    bool inheritItalic = false,
    bool inheritColor = false,
    bool inheritLineHeight = false,
    bool inheritLetterSpacing = false,
    JsonTextBinding? binding,
    bool clearBinding = false,
    Map<SuperValueProperty, JsonTextBinding>? propertyBindings,
    SuperTextFieldConfig? field,
    ValueConfigStates? states,
    bool clearStates = false,
  }) => SuperValueConfig(
    mode: mode ?? this.mode,
    kind: kind ?? this.kind,
    initialText: initialText ?? this.initialText,
    initialBool: initialBool ?? this.initialBool,
    label: label ?? this.label,
    placeholder: placeholder ?? this.placeholder,
    enabled: enabled ?? this.enabled,
    readOnly: readOnly ?? this.readOnly,
    obscureText: obscureText ?? this.obscureText,
    minLines: minLines ?? this.minLines,
    maxLines: maxLines ?? this.maxLines,
    fontFamily: inheritFontFamily ? null : fontFamily ?? this.fontFamily,
    fontSize: inheritFontSize ? null : fontSize ?? this.fontSize,
    fontWeight: inheritFontWeight ? null : fontWeight ?? this.fontWeight,
    italic: inheritItalic ? null : italic ?? this.italic,
    color: inheritColor ? null : color ?? this.color,
    textAlign: textAlign ?? this.textAlign,
    lineHeight: inheritLineHeight ? null : lineHeight ?? this.lineHeight,
    letterSpacing: inheritLetterSpacing
        ? null
        : letterSpacing ?? this.letterSpacing,
    binding: clearBinding ? null : binding ?? this.binding,
    propertyBindings: propertyBindings ?? this.propertyBindings,
    field: field ?? this.field,
    states: clearStates ? null : states ?? this.states,
  );

  Map<String, Object?> toJson() {
    validate();
    return {
      'mode': mode.name,
      if (kind != SuperValueKind.text) 'kind': kind.name,
      if (!obscureText) 'initialText': initialText,
      if (initialBool) 'initialBool': initialBool,
      'label': label,
      'placeholder': placeholder,
      'enabled': enabled,
      'readOnly': readOnly,
      'obscureText': obscureText,
      'minLines': minLines,
      'maxLines': maxLines,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'fontWeight': fontWeight?.value,
      'italic': italic,
      'color': color?.toARGB32(),
      'textAlign': textAlign.name,
      'lineHeight': lineHeight,
      'letterSpacing': letterSpacing,
      if (binding != null) 'binding': binding!.toJson(),
      if (propertyBindings.isNotEmpty)
        'propertyBindings': {
          for (final entry in propertyBindings.entries)
            entry.key.name: entry.value.toJson(),
        },
      if (field != const SuperTextFieldConfig()) 'field': field.toJson(),
      if (states != null) 'states': states!.toJson(),
    };
  }

  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperValueConfig();
    return {
      if (mode != d.mode) 'mode': mode.name,
      if (kind != SuperValueKind.text) 'kind': kind.name,
      if (!obscureText && initialText.isNotEmpty) 'initialText': initialText,
      if (initialBool) 'initialBool': initialBool,
      if (label.isNotEmpty) 'label': label,
      if (placeholder.isNotEmpty) 'placeholder': placeholder,
      if (enabled != d.enabled) 'enabled': enabled,
      if (readOnly != d.readOnly) 'readOnly': readOnly,
      if (obscureText != d.obscureText) 'obscureText': obscureText,
      if (minLines != d.minLines) 'minLines': minLines,
      if (maxLines != d.maxLines) 'maxLines': maxLines,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': fontWeight!.value,
      if (italic != null) 'italic': italic,
      if (color != null) 'color': JsonColor.toHex(color!),
      if (textAlign != d.textAlign) 'textAlign': textAlign.name,
      if (lineHeight != null) 'lineHeight': lineHeight,
      if (letterSpacing != null) 'letterSpacing': letterSpacing,
      if (binding != null) 'binding': binding!.toCompactJson(),
      if (propertyBindings.isNotEmpty)
        'propertyBindings': {
          for (final entry in propertyBindings.entries)
            entry.key.name: entry.value.toCompactJson(),
        },
      if (field != const SuperTextFieldConfig())
        'field': field.toCompactJson(),
      if (states != null) 'states': states!.toCompactJson(),
    };
  }

  /// Applique un patch JSON partiel sur cette configuration en conservant
  /// toutes les propriétés non mentionnées dans [patch].
  SuperValueConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperValueConfig.fromJson(patch, fallback: this);

  static FontWeight? _parseFontWeight(Object? weight) {
    if (weight == null) return null;
    if (weight is int) {
      return FontWeight.values.where((w) => w.value == weight).firstOrNull;
    }
    if (weight is String) {
      return switch (weight.trim().toLowerCase()) {
        'thin' || 'w100' || '100' => FontWeight.w100,
        'extralight' || 'w200' || '200' => FontWeight.w200,
        'light' || 'w300' || '300' => FontWeight.w300,
        'normal' || 'regular' || 'w400' || '400' => FontWeight.w400,
        'medium' || 'w500' || '500' => FontWeight.w500,
        'semibold' || 'w600' || '600' => FontWeight.w600,
        'bold' || 'w700' || '700' => FontWeight.w700,
        'extrabold' || 'w800' || '800' => FontWeight.w800,
        'black' || 'w900' || '900' => FontWeight.w900,
        _ => null,
      };
    }
    return null;
  }

  factory SuperValueConfig.fromJson(
    Object? value, {
    SuperValueConfig fallback = const SuperValueConfig(),
  }) {
    if (value is! Map) {
      throw const FormatException('Invalid Value configuration.');
    }
    const keys = {
      'mode',
      'kind',
      'initialText',
      'text',
      'initialBool',
      'value',
      'label',
      'placeholder',
      'enabled',
      'readOnly',
      'obscureText',
      'minLines',
      'maxLines',
      'fontFamily',
      'fontSize',
      'fontWeight',
      'italic',
      'color',
      'textAlign',
      'lineHeight',
      'letterSpacing',
      'binding',
      'propertyBindings',
      'field',
      'states',
    };
    if (value.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown Value preference.');
    }
    T field<T>(String key, T fallbackVal) {
      if (!value.containsKey(key)) return fallbackVal;
      final result = value[key];
      if (result is! T) throw FormatException('Invalid Value "$key".');
      return result;
    }

    double? number(String key, double? fallbackVal) {
      if (!value.containsKey(key)) return fallbackVal;
      final result = value[key];
      if (result == null) return null;
      if (result is! num || !result.isFinite) {
        throw FormatException('Invalid Value "$key".');
      }
      return result.toDouble();
    }

    final mode = SuperValueMode.values
        .where((mode) => mode.name == field('mode', fallback.mode.name))
        .firstOrNull;
    final rawKind = field('kind', fallback.kind.name);
    final kind = switch (rawKind) {
      'switch' => SuperValueKind.switchControl,
      _ =>
        SuperValueKind.values
            .where((candidate) => candidate.name == rawKind)
            .firstOrNull,
    };
    final align = TextAlign.values
        .where(
          (align) => align.name == field('textAlign', fallback.textAlign.name),
        )
        .firstOrNull;
    final hasWeight = value.containsKey('fontWeight');
    final weight = value['fontWeight'];
    final fontWeight = hasWeight
        ? _parseFontWeight(weight)
        : fallback.fontWeight;
    final hasColor = value.containsKey('color');
    final rawColor = value['color'];
    final Color? parsedColor;
    try {
      parsedColor = hasColor
          ? JsonColor.parseNullable(rawColor, 'color')
          : fallback.color;
    } on FormatException {
      throw const FormatException('Invalid Value style.');
    }
    final hasFamily = value.containsKey('fontFamily');
    final family = hasFamily ? value['fontFamily'] : fallback.fontFamily;
    if (mode == null ||
        kind == null ||
        align == null ||
        (hasWeight && weight != null && fontWeight == null) ||
        (family != null && family is! String)) {
      throw const FormatException('Invalid Value style.');
    }
    final rawPropertyBindings = value['propertyBindings'];
    if (rawPropertyBindings != null && rawPropertyBindings is! Map) {
      throw const FormatException('Invalid Value property bindings.');
    }
    final Map<SuperValueProperty, JsonTextBinding> propertyBindings;
    if (!value.containsKey('propertyBindings')) {
      propertyBindings = fallback.propertyBindings;
    } else {
      propertyBindings = <SuperValueProperty, JsonTextBinding>{};
      for (final entry in (rawPropertyBindings as Map? ?? {}).entries) {
        if (entry.key is! String) {
          throw const FormatException('Invalid Value property binding.');
        }
        final property = SuperValueProperty.values
            .where((candidate) => candidate.name == entry.key)
            .firstOrNull;
        if (property == null ||
            (entry.value is! Map && entry.value is! String)) {
          throw const FormatException('Invalid Value property binding.');
        }
        propertyBindings[property] = JsonTextBinding.fromJson(entry.value);
      }
    }

    var resolvedInitialText = fallback.initialText;
    if (value.containsKey('initialText')) {
      resolvedInitialText = field('initialText', fallback.initialText);
    } else if (value.containsKey('text')) {
      resolvedInitialText = field('text', fallback.initialText);
    } else if (value.containsKey('value') && value['value'] is String) {
      resolvedInitialText = value['value'] as String;
    }

    var resolvedInitialBool = fallback.initialBool;
    if (value.containsKey('initialBool')) {
      resolvedInitialBool = field('initialBool', fallback.initialBool);
    } else if (value.containsKey('value') && value['value'] is bool) {
      resolvedInitialBool = value['value'] as bool;
    } else if (value.containsKey('value') &&
        value['value'] is! String &&
        value['value'] is! bool) {
      throw const FormatException('Invalid Value "value".');
    }

    final resolvedObscure = field('obscureText', fallback.obscureText);
    if (resolvedObscure &&
        !value.containsKey('initialText') &&
        !value.containsKey('text')) {
      resolvedInitialText = '';
    }

    final result = SuperValueConfig(
      mode: mode,
      kind: kind,
      textAlign: align,
      initialText: resolvedInitialText,
      initialBool: resolvedInitialBool,
      label: field('label', fallback.label),
      placeholder: field('placeholder', fallback.placeholder),
      enabled: field('enabled', fallback.enabled),
      readOnly: field('readOnly', fallback.readOnly),
      obscureText: resolvedObscure,
      minLines: field<int>('minLines', fallback.minLines),
      maxLines: field<int>('maxLines', fallback.maxLines),
      fontFamily: family as String?,
      fontSize: number('fontSize', fallback.fontSize),
      fontWeight: fontWeight,
      italic: field<bool?>('italic', fallback.italic),
      color: parsedColor,
      lineHeight: number('lineHeight', fallback.lineHeight),
      letterSpacing: number('letterSpacing', fallback.letterSpacing),
      binding: !value.containsKey('binding')
          ? fallback.binding
          : value['binding'] == null
          ? null
          : JsonTextBinding.fromJson(value['binding']),
      propertyBindings: propertyBindings,
      field: value.containsKey('field')
          ? SuperTextFieldConfig.fromJson(
              value['field'],
              fallback: fallback.field,
            )
          : fallback.field,
      states: !value.containsKey('states')
          ? fallback.states
          : value['states'] == null
          ? null
          : ValueConfigStates.fromJson(value['states']),
    );
    try {
      result.validate();
    } on ArgumentError {
      throw const FormatException('Invalid Value configuration.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperValueConfig &&
      mode == other.mode &&
      kind == other.kind &&
      initialText == other.initialText &&
      initialBool == other.initialBool &&
      label == other.label &&
      placeholder == other.placeholder &&
      enabled == other.enabled &&
      readOnly == other.readOnly &&
      obscureText == other.obscureText &&
      minLines == other.minLines &&
      maxLines == other.maxLines &&
      fontFamily == other.fontFamily &&
      fontSize == other.fontSize &&
      fontWeight == other.fontWeight &&
      italic == other.italic &&
      color == other.color &&
      textAlign == other.textAlign &&
      lineHeight == other.lineHeight &&
      letterSpacing == other.letterSpacing &&
      binding == other.binding &&
      mapEquals(propertyBindings, other.propertyBindings) &&
      field == other.field &&
      states == other.states;

  @override
  int get hashCode => Object.hashAll([
    mode,
    kind,
    initialText,
    initialBool,
    label,
    placeholder,
    enabled,
    readOnly,
    obscureText,
    minLines,
    maxLines,
    fontFamily,
    fontSize,
    fontWeight,
    italic,
    color,
    textAlign,
    lineHeight,
    letterSpacing,
    binding,
    Object.hashAllUnordered(
      propertyBindings.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    field,
    states,
  ]);
}
