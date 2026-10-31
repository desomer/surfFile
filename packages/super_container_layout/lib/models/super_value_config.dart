import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show mapEquals, setEquals;

import 'component_config.dart';
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
class SuperValueConfig extends ComponentConfig {
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

  @override
  String get componentType => 'value';

  @override
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

  @override
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
        'propertyBindings': JsonReader.encodePropertyBindings(propertyBindings),
      if (field != const SuperTextFieldConfig()) 'field': field.toJson(),
      if (states != null) 'states': states!.toJson(),
    };
  }

  @override
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
        'propertyBindings': JsonReader.encodePropertyBindings(
          propertyBindings,
          compact: true,
        ),
      if (field != const SuperTextFieldConfig())
        'field': field.toCompactJson(),
      if (states != null) 'states': states!.toCompactJson(),
    };
  }

  /// Applique un patch JSON partiel sur cette configuration en conservant
  /// toutes les propriétés non mentionnées dans [patch].
  @override
  SuperValueConfig patchFromJson(Map<Object?, Object?> patch) =>
      SuperValueConfig.fromJson(patch, fallback: this);

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
    T field<T>(String key, T fallbackVal) =>
        JsonReader.field(value, key, fallbackVal, context: 'Value');
    double? number(String key, double? fallbackVal) =>
        JsonReader.nullableDouble(value, key, fallbackVal, context: 'Value');

    final mode = JsonReader.enumByName(
      SuperValueMode.values,
      field('mode', fallback.mode.name),
    );
    final kind = JsonReader.enumByName(
      SuperValueKind.values,
      field('kind', fallback.kind.name),
      const {'switch': SuperValueKind.switchControl},
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
    final parsedColor = JsonReader.nullableColor(
      value,
      'color',
      fallback.color,
      errorMessage: 'Invalid Value style.',
    );
    final hasFamily = value.containsKey('fontFamily');
    final family = hasFamily ? value['fontFamily'] : fallback.fontFamily;
    if (mode == null ||
        kind == null ||
        align == null ||
        (hasWeight && weight != null && fontWeight == null) ||
        (family != null && family is! String)) {
      throw const FormatException('Invalid Value style.');
    }
    final propertyBindings = JsonReader.readPropertyBindings(
      value,
      SuperValueProperty.values,
      fallback.propertyBindings,
      context: 'Value',
    );

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

String _formatValueNumber(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// Résumé des propriétés d'un [SuperValueConfig] pour l'info-bulle du menu contextuel.
String formatSuperValueTooltip({
  required String title,
  required SuperValueConfig config,
}) {
  final modeLabel =
      config.mode == SuperValueMode.input ? 'Saisie' : 'Affichage';
  final kindLabel = switch (config.kind) {
    SuperValueKind.text => 'Texte',
    SuperValueKind.checkbox => 'Case à cocher',
    SuperValueKind.switchControl => 'Interrupteur',
  };
  final flags = <String>[
    if (!config.enabled) 'Désactivé',
    if (config.readOnly) 'Lecture seule',
    if (config.obscureText) 'Masqué',
  ];
  final contentParts = <String>[
    if (config.binding != null)
      'Liaison : ${config.binding!.repositoryId ?? 'Hérité'} → ${config.binding!.path}'
    else if (config.kind.isBoolean)
      'Valeur : ${config.initialBool ? 'Vrai' : 'Faux'}'
    else if (config.obscureText)
      'Valeur : ••••••'
    else
      'Texte : ${config.initialText.isEmpty ? 'Vide' : config.initialText}',
    if (config.label.isNotEmpty) 'Libellé : ${config.label}',
    if (config.placeholder.isNotEmpty) 'Placeholder : ${config.placeholder}',
  ];
  final styleParts = <String>[
    'Police : ${config.fontFamily ?? 'Auto'}',
    'Taille : ${config.fontSize != null ? '${_formatValueNumber(config.fontSize!)} px' : 'Auto'}',
    'Alignement : ${config.textAlign.name}',
    if (!config.kind.isBoolean && (config.minLines > 1 || config.maxLines > 1))
      'Lignes : ${config.minLines == config.maxLines ? '${config.maxLines}' : '${config.minLines}–${config.maxLines}'}',
    if (config.color != null) 'Couleur : ${JsonColor.toHex(config.color!)}',
  ];
  return [
    title,
    [
      'Mode : $modeLabel',
      'Type : $kindLabel',
      ...flags,
    ].join(' · '),
    contentParts.join(' · '),
    styleParts.join(' · '),
  ].join('\n');
}

