import 'package:material_ui/material_ui.dart';

enum TextFieldVariant { theme, filled, outlined, underline, borderless }

enum TextFieldFilter { none, digits, decimal, letters, pattern }

enum TextFieldSuffix { decoration, clear, visibility }

enum TextFieldKeyboard {
  automatic,
  text,
  multiline,
  email,
  phone,
  url,
  number,
  decimal,
  signedDecimal,
}

enum TextFieldAction {
  automatic,
  done,
  next,
  previous,
  search,
  send,
  go,
  newline,
}

enum TextFieldVerticalAlign { automatic, top, center, bottom }

/// Constant icons keep release icon tree-shaking available.
enum TextFieldIcon {
  person(Icons.person_outline),
  email(Icons.email_outlined),
  phone(Icons.phone_outlined),
  search(Icons.search),
  lock(Icons.lock_outline),
  link(Icons.link),
  home(Icons.home_outlined),
  calendar(Icons.calendar_today_outlined),
  info(Icons.info_outline),
  check(Icons.check);

  const TextFieldIcon(this.data);
  final IconData data;
}

@immutable
class SuperTextFieldConfig {
  const SuperTextFieldConfig({
    this.variant = TextFieldVariant.theme,
    this.fillColor,
    this.focusFillColor,
    this.disabledFillColor,
    this.errorFillColor,
    this.borderColor,
    this.focusBorderColor,
    this.disabledBorderColor,
    this.errorBorderColor,
    this.radius,
    this.borderWidth,
    this.horizontalPadding,
    this.verticalPadding,
    this.dense,
    this.prefixText = '',
    this.suffixText = '',
    this.prefixIcon,
    this.suffixIcon,
    this.suffix = TextFieldSuffix.decoration,
    this.helperText = '',
    this.errorText = '',
    this.showCounter = false,
    this.maxLength,
    this.filter = TextFieldFilter.none,
    this.pattern = '',
    this.keyboard = TextFieldKeyboard.automatic,
    this.action = TextFieldAction.automatic,
    this.capitalization = TextCapitalization.none,
    this.verticalAlign = TextFieldVerticalAlign.automatic,
    this.floatingLabel,
    this.autocorrect = true,
    this.suggestions = true,
  });

  final TextFieldVariant variant;
  final Color? fillColor, focusFillColor, disabledFillColor, errorFillColor;
  final Color? borderColor,
      focusBorderColor,
      disabledBorderColor,
      errorBorderColor;
  final double? radius, borderWidth, horizontalPadding, verticalPadding;
  final bool? dense;
  final String prefixText, suffixText, helperText, errorText, pattern;
  final TextFieldIcon? prefixIcon, suffixIcon;
  final TextFieldSuffix suffix;
  final bool showCounter, autocorrect, suggestions;
  final int? maxLength;
  final TextFieldFilter filter;
  final TextFieldKeyboard keyboard;
  final TextFieldAction action;
  final TextCapitalization capitalization;
  final TextFieldVerticalAlign verticalAlign;
  final FloatingLabelBehavior? floatingLabel;

  void validate() {
    for (final value in [
      radius,
      borderWidth,
      horizontalPadding,
      verticalPadding,
    ]) {
      if (value != null && (!value.isFinite || value < 0)) {
        throw const FormatException('Dimensions de champ invalides.');
      }
    }
    if (maxLength != null && maxLength! < 1) {
      throw const FormatException('La longueur maximale doit être positive.');
    }
    if (filter == TextFieldFilter.pattern) {
      RegExp expression;
      try {
        expression = RegExp(pattern, unicode: true);
      } on FormatException {
        throw const FormatException('Expression régulière invalide.');
      }
      if (pattern.isEmpty ||
          expression.hasMatch('') ||
          expression
              .allMatches('a0 -_é\n')
              .any((match) => match.start == match.end)) {
        throw const FormatException(
          'Le filtre ne doit pas accepter de correspondance vide.',
        );
      }
    }
  }

  void validateFor({required bool obscureText, required int maxLines}) {
    validate();
    if (action == TextFieldAction.newline &&
        (maxLines == 1 ||
            obscureText ||
            (keyboard != TextFieldKeyboard.automatic &&
                keyboard != TextFieldKeyboard.multiline))) {
      throw const FormatException(
        'L’action Nouvelle ligne nécessite un champ multiligne et un clavier multiligne.',
      );
    }
    if (obscureText && keyboard == TextFieldKeyboard.multiline) {
      throw const FormatException(
        'Un mot de passe ne peut pas utiliser un clavier multiligne.',
      );
    }
  }

  SuperTextFieldConfig copyWith({
    TextFieldVariant? variant,
    TextFieldSuffix? suffix,
    TextFieldFilter? filter,
    TextFieldKeyboard? keyboard,
    TextFieldAction? action,
    TextCapitalization? capitalization,
    TextFieldVerticalAlign? verticalAlign,
    FloatingLabelBehavior? floatingLabel,
    bool? showCounter,
    bool? autocorrect,
    bool? suggestions,
    String? prefixText,
    String? suffixText,
    String? helperText,
    String? errorText,
    String? pattern,
    Color? fillColor,
    Color? focusFillColor,
    Color? disabledFillColor,
    Color? errorFillColor,
    Color? borderColor,
    Color? focusBorderColor,
    Color? disabledBorderColor,
    Color? errorBorderColor,
    double? radius,
    double? borderWidth,
    double? horizontalPadding,
    double? verticalPadding,
    bool? dense,
    int? maxLength,
    TextFieldIcon? prefixIcon,
    TextFieldIcon? suffixIcon,
    bool inheritFillColor = false,
    bool inheritFocusFillColor = false,
    bool inheritDisabledFillColor = false,
    bool inheritErrorFillColor = false,
    bool inheritBorderColor = false,
    bool inheritFocusBorderColor = false,
    bool inheritDisabledBorderColor = false,
    bool inheritErrorBorderColor = false,
    bool inheritRadius = false,
    bool inheritBorderWidth = false,
    bool inheritHorizontalPadding = false,
    bool inheritVerticalPadding = false,
    bool inheritDense = false,
    bool clearMaxLength = false,
    bool clearPrefixIcon = false,
    bool clearSuffixIcon = false,
    bool inheritFloatingLabel = false,
  }) => SuperTextFieldConfig(
    variant: variant ?? this.variant,
    suffix: suffix ?? this.suffix,
    filter: filter ?? this.filter,
    keyboard: keyboard ?? this.keyboard,
    action: action ?? this.action,
    capitalization: capitalization ?? this.capitalization,
    verticalAlign: verticalAlign ?? this.verticalAlign,
    floatingLabel: inheritFloatingLabel
        ? null
        : floatingLabel ?? this.floatingLabel,
    showCounter: showCounter ?? this.showCounter,
    autocorrect: autocorrect ?? this.autocorrect,
    suggestions: suggestions ?? this.suggestions,
    prefixText: prefixText ?? this.prefixText,
    suffixText: suffixText ?? this.suffixText,
    helperText: helperText ?? this.helperText,
    errorText: errorText ?? this.errorText,
    pattern: pattern ?? this.pattern,
    fillColor: inheritFillColor ? null : fillColor ?? this.fillColor,
    focusFillColor: inheritFocusFillColor
        ? null
        : focusFillColor ?? this.focusFillColor,
    disabledFillColor: inheritDisabledFillColor
        ? null
        : disabledFillColor ?? this.disabledFillColor,
    errorFillColor: inheritErrorFillColor
        ? null
        : errorFillColor ?? this.errorFillColor,
    borderColor: inheritBorderColor ? null : borderColor ?? this.borderColor,
    focusBorderColor: inheritFocusBorderColor
        ? null
        : focusBorderColor ?? this.focusBorderColor,
    disabledBorderColor: inheritDisabledBorderColor
        ? null
        : disabledBorderColor ?? this.disabledBorderColor,
    errorBorderColor: inheritErrorBorderColor
        ? null
        : errorBorderColor ?? this.errorBorderColor,
    radius: inheritRadius ? null : radius ?? this.radius,
    borderWidth: inheritBorderWidth ? null : borderWidth ?? this.borderWidth,
    horizontalPadding: inheritHorizontalPadding
        ? null
        : horizontalPadding ?? this.horizontalPadding,
    verticalPadding: inheritVerticalPadding
        ? null
        : verticalPadding ?? this.verticalPadding,
    dense: inheritDense ? null : dense ?? this.dense,
    maxLength: clearMaxLength ? null : maxLength ?? this.maxLength,
    prefixIcon: clearPrefixIcon ? null : prefixIcon ?? this.prefixIcon,
    suffixIcon: clearSuffixIcon ? null : suffixIcon ?? this.suffixIcon,
  );

  Map<String, Object?> toJson() => {
    'variant': variant.name,
    'fillColor': fillColor?.toARGB32(),
    'focusFillColor': focusFillColor?.toARGB32(),
    'disabledFillColor': disabledFillColor?.toARGB32(),
    'errorFillColor': errorFillColor?.toARGB32(),
    'borderColor': borderColor?.toARGB32(),
    'focusBorderColor': focusBorderColor?.toARGB32(),
    'disabledBorderColor': disabledBorderColor?.toARGB32(),
    'errorBorderColor': errorBorderColor?.toARGB32(),
    'radius': radius,
    'borderWidth': borderWidth,
    'horizontalPadding': horizontalPadding,
    'verticalPadding': verticalPadding,
    'dense': dense,
    'prefixText': prefixText,
    'suffixText': suffixText,
    'prefixIcon': prefixIcon?.name,
    'suffixIcon': suffixIcon?.name,
    'suffix': suffix.name,
    'helperText': helperText,
    'errorText': errorText,
    'showCounter': showCounter,
    'maxLength': maxLength,
    'filter': filter.name,
    'pattern': pattern,
    'keyboard': keyboard.name,
    'action': action.name,
    'capitalization': capitalization.name,
    'verticalAlign': verticalAlign.name,
    'floatingLabel': floatingLabel?.name,
    'autocorrect': autocorrect,
    'suggestions': suggestions,
  };

  factory SuperTextFieldConfig.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Options de champ invalides.');
    }
    final defaults = const SuperTextFieldConfig().toJson();
    if (json.keys.any((key) => !defaults.containsKey(key))) {
      throw const FormatException('Option de champ inconnue.');
    }
    T field<T>(String key, T fallback) {
      final value = json.containsKey(key) ? json[key] : fallback;
      if (value is! T) {
        throw FormatException('Option de champ invalide : $key.');
      }
      return value;
    }

    T choice<T extends Enum>(String key, List<T> values, T fallback) {
      final name = field(key, fallback.name);
      final value = values.where((value) => value.name == name).firstOrNull;
      if (value == null) {
        throw FormatException('Option de champ invalide : $key.');
      }
      return value;
    }

    Color? color(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int || value < 0 || value > 0xFFFFFFFF) {
        throw FormatException('Couleur de champ invalide : $key.');
      }
      return Color(value);
    }

    double? number(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite || value < 0) {
        throw FormatException('Dimension de champ invalide : $key.');
      }
      return value.toDouble();
    }

    TextFieldIcon? icon(String key) {
      if (json[key] == null) return null;
      return choice(key, TextFieldIcon.values, TextFieldIcon.person);
    }

    final result = SuperTextFieldConfig(
      variant: choice(
        'variant',
        TextFieldVariant.values,
        TextFieldVariant.theme,
      ),
      fillColor: color('fillColor'),
      focusFillColor: color('focusFillColor'),
      disabledFillColor: color('disabledFillColor'),
      errorFillColor: color('errorFillColor'),
      borderColor: color('borderColor'),
      focusBorderColor: color('focusBorderColor'),
      disabledBorderColor: color('disabledBorderColor'),
      errorBorderColor: color('errorBorderColor'),
      radius: number('radius'),
      borderWidth: number('borderWidth'),
      horizontalPadding: number('horizontalPadding'),
      verticalPadding: number('verticalPadding'),
      dense: field<bool?>('dense', null),
      prefixText: field('prefixText', ''),
      suffixText: field('suffixText', ''),
      prefixIcon: icon('prefixIcon'),
      suffixIcon: icon('suffixIcon'),
      suffix: choice(
        'suffix',
        TextFieldSuffix.values,
        TextFieldSuffix.decoration,
      ),
      helperText: field('helperText', ''),
      errorText: field('errorText', ''),
      showCounter: field('showCounter', false),
      maxLength: field<int?>('maxLength', null),
      filter: choice('filter', TextFieldFilter.values, TextFieldFilter.none),
      pattern: field('pattern', ''),
      keyboard: choice(
        'keyboard',
        TextFieldKeyboard.values,
        TextFieldKeyboard.automatic,
      ),
      action: choice(
        'action',
        TextFieldAction.values,
        TextFieldAction.automatic,
      ),
      capitalization: choice(
        'capitalization',
        TextCapitalization.values,
        TextCapitalization.none,
      ),
      verticalAlign: choice(
        'verticalAlign',
        TextFieldVerticalAlign.values,
        TextFieldVerticalAlign.automatic,
      ),
      floatingLabel: json['floatingLabel'] == null
          ? null
          : choice(
              'floatingLabel',
              FloatingLabelBehavior.values,
              FloatingLabelBehavior.auto,
            ),
      autocorrect: field('autocorrect', true),
      suggestions: field('suggestions', true),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperTextFieldConfig && _equal(toJson(), other.toJson());
  static bool _equal(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);
  @override
  int get hashCode => Object.hashAll(toJson().values);
}
