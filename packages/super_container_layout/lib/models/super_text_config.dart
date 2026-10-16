import 'package:material_ui/material_ui.dart';

enum SuperTextMode { display, input }

@immutable
class SuperTextConfig {
  const SuperTextConfig({
    this.mode = SuperTextMode.display,
    this.initialText = '',
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
  });

  final SuperTextMode mode;
  final String initialText;
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

  void validate() {
    if (minLines < 1 ||
        maxLines < minLines ||
        (obscureText &&
            (initialText.isNotEmpty || minLines != 1 || maxLines != 1)) ||
        (fontFamily != null && fontFamily!.trim().isEmpty) ||
        (fontSize != null && (!fontSize!.isFinite || fontSize! <= 0)) ||
        (lineHeight != null && (!lineHeight!.isFinite || lineHeight! <= 0)) ||
        (letterSpacing != null && !letterSpacing!.isFinite)) {
      throw ArgumentError('Invalid SuperText configuration.');
    }
  }

  SuperTextConfig copyWith({
    SuperTextMode? mode,
    String? initialText,
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
  }) => SuperTextConfig(
    mode: mode ?? this.mode,
    initialText: initialText ?? this.initialText,
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
  );

  Map<String, Object?> toJson() {
    validate();
    return {
      'mode': mode.name,
      if (!obscureText) 'initialText': initialText,
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
    };
  }

  factory SuperTextConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid SuperText configuration.');
    }
    const keys = {
      'mode',
      'initialText',
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
    };
    if (value.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown SuperText preference.');
    }
    T field<T>(String key, T fallback) {
      if (!value.containsKey(key)) return fallback;
      final result = value[key];
      if (result is! T) throw FormatException('Invalid SuperText "$key".');
      return result;
    }

    double? number(String key) {
      final result = value[key];
      if (result == null) return null;
      if (result is! num || !result.isFinite) {
        throw FormatException('Invalid SuperText "$key".');
      }
      return result.toDouble();
    }

    final mode = SuperTextMode.values
        .where((mode) => mode.name == field('mode', 'display'))
        .firstOrNull;
    final align = TextAlign.values
        .where((align) => align.name == field('textAlign', 'start'))
        .firstOrNull;
    final weight = value['fontWeight'];
    final fontWeight = FontWeight.values
        .where((w) => w.value == weight)
        .firstOrNull;
    final color = value['color'];
    final family = value['fontFamily'];
    if (mode == null ||
        align == null ||
        (weight != null && (weight is! int || fontWeight == null)) ||
        (color != null && (color is! int || color < 0 || color > 0xFFFFFFFF)) ||
        (family != null && family is! String)) {
      throw const FormatException('Invalid SuperText style.');
    }
    final result = SuperTextConfig(
      mode: mode,
      textAlign: align,
      initialText: field('initialText', ''),
      label: field('label', ''),
      placeholder: field('placeholder', ''),
      enabled: field('enabled', true),
      readOnly: field('readOnly', false),
      obscureText: field('obscureText', false),
      minLines: field<int>('minLines', 1),
      maxLines: field<int>('maxLines', 1),
      fontFamily: family as String?,
      fontSize: number('fontSize'),
      fontWeight: fontWeight,
      italic: field<bool?>('italic', null),
      color: color == null ? null : Color(color as int),
      lineHeight: number('lineHeight'),
      letterSpacing: number('letterSpacing'),
    );
    try {
      result.validate();
    } on ArgumentError {
      throw const FormatException('Invalid SuperText configuration.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperTextConfig &&
      mode == other.mode &&
      initialText == other.initialText &&
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
      letterSpacing == other.letterSpacing;

  @override
  int get hashCode => Object.hashAll([
    mode,
    initialText,
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
  ]);
}
