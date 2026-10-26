import 'package:material_ui/material_ui.dart';

import 'json_syntax.dart';
import 'material_icon_catalog.dart';

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
  check(Icons.check),
  edit(Icons.edit_outlined),
  location_on(Icons.location_on_outlined),
  credit_card(Icons.credit_card_outlined),
  payments(Icons.payments_outlined),
  work(Icons.work_outline),
  folder(Icons.folder_outlined),
  description(Icons.description_outlined),
  attach_file(Icons.attach_file),
  schedule(Icons.schedule),
  label(Icons.label_outline),
  star(Icons.star_border),
  favorite(Icons.favorite_border),
  warning(Icons.warning_amber_outlined),
  error(Icons.error_outline),
  help(Icons.help_outline),
  key(Icons.key_outlined),
  shield(Icons.shield_outlined),
  badge(Icons.badge_outlined),
  group(Icons.group_outlined),
  language(Icons.language),
  alternate_email(Icons.alternate_email),
  qr_code(Icons.qr_code_2),
  code(Icons.code),
  filter_list(Icons.filter_list),
  tune(Icons.tune),
  shopping_cart(Icons.shopping_cart_outlined),
  inventory(Icons.inventory_2_outlined),
  local_shipping(Icons.local_shipping_outlined);

  const TextFieldIcon(this.data);
  final IconData data;

  String get displayLabel => MaterialIconCatalog.labelOf(name);
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

  Map<String, Object?> toCompactJson() {
    const d = SuperTextFieldConfig();
    return {
      if (variant != d.variant) 'variant': variant.name,
      if (fillColor != null) 'fillColor': JsonColor.toHex(fillColor!),
      if (focusFillColor != null)
        'focusFillColor': JsonColor.toHex(focusFillColor!),
      if (disabledFillColor != null)
        'disabledFillColor': JsonColor.toHex(disabledFillColor!),
      if (errorFillColor != null)
        'errorFillColor': JsonColor.toHex(errorFillColor!),
      if (borderColor != null) 'borderColor': JsonColor.toHex(borderColor!),
      if (focusBorderColor != null)
        'focusBorderColor': JsonColor.toHex(focusBorderColor!),
      if (disabledBorderColor != null)
        'disabledBorderColor': JsonColor.toHex(disabledBorderColor!),
      if (errorBorderColor != null)
        'errorBorderColor': JsonColor.toHex(errorBorderColor!),
      if (radius != null) 'radius': radius,
      if (borderWidth != null) 'borderWidth': borderWidth,
      if (horizontalPadding != null) 'horizontalPadding': horizontalPadding,
      if (verticalPadding != null) 'verticalPadding': verticalPadding,
      if (dense != null) 'dense': dense,
      if (prefixText.isNotEmpty) 'prefixText': prefixText,
      if (suffixText.isNotEmpty) 'suffixText': suffixText,
      if (prefixIcon != null) 'prefixIcon': prefixIcon!.name,
      if (suffixIcon != null) 'suffixIcon': suffixIcon!.name,
      if (suffix != d.suffix) 'suffix': suffix.name,
      if (helperText.isNotEmpty) 'helperText': helperText,
      if (errorText.isNotEmpty) 'errorText': errorText,
      if (showCounter != d.showCounter) 'showCounter': showCounter,
      if (maxLength != null) 'maxLength': maxLength,
      if (filter != d.filter) 'filter': filter.name,
      if (pattern.isNotEmpty) 'pattern': pattern,
      if (keyboard != d.keyboard) 'keyboard': keyboard.name,
      if (action != d.action) 'action': action.name,
      if (capitalization != d.capitalization)
        'capitalization': capitalization.name,
      if (verticalAlign != d.verticalAlign) 'verticalAlign': verticalAlign.name,
      if (floatingLabel != null) 'floatingLabel': floatingLabel!.name,
      if (autocorrect != d.autocorrect) 'autocorrect': autocorrect,
      if (suggestions != d.suggestions) 'suggestions': suggestions,
    };
  }

  factory SuperTextFieldConfig.fromJson(
    Object? json, {
    SuperTextFieldConfig fallback = const SuperTextFieldConfig(),
  }) {
    if (json is! Map) {
      throw const FormatException('Options de champ invalides.');
    }
    final defaults = fallback.toJson();
    if (json.keys.any((key) => !defaults.containsKey(key))) {
      throw const FormatException('Option de champ inconnue.');
    }
    T field<T>(String key, T fallbackVal) {
      final value = json.containsKey(key) ? json[key] : fallbackVal;
      if (value is! T) {
        throw FormatException('Option de champ invalide : $key.');
      }
      return value;
    }

    T choice<T extends Enum>(String key, List<T> values, T fallbackVal) {
      final name = field(key, fallbackVal.name);
      final value = values.where((value) => value.name == name).firstOrNull;
      if (value == null) {
        throw FormatException('Option de champ invalide : $key.');
      }
      return value;
    }

    Color? color(String key, Color? defaultColor) {
      if (!json.containsKey(key)) return defaultColor;
      final value = json[key];
      if (value == null) return null;
      try {
        return JsonColor.parse(value, key);
      } on FormatException {
        throw FormatException('Couleur de champ invalide : $key.');
      }
    }

    double? number(String key, double? defaultNum) {
      if (!json.containsKey(key)) return defaultNum;
      final value = json[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite || value < 0) {
        throw FormatException('Dimension de champ invalide : $key.');
      }
      return value.toDouble();
    }

    TextFieldIcon? icon(String key, TextFieldIcon? defaultIcon) {
      if (!json.containsKey(key)) return defaultIcon;
      if (json[key] == null) return null;
      return choice(key, TextFieldIcon.values, TextFieldIcon.person);
    }

    final result = SuperTextFieldConfig(
      variant: choice(
        'variant',
        TextFieldVariant.values,
        fallback.variant,
      ),
      fillColor: color('fillColor', fallback.fillColor),
      focusFillColor: color('focusFillColor', fallback.focusFillColor),
      disabledFillColor: color('disabledFillColor', fallback.disabledFillColor),
      errorFillColor: color('errorFillColor', fallback.errorFillColor),
      borderColor: color('borderColor', fallback.borderColor),
      focusBorderColor: color('focusBorderColor', fallback.focusBorderColor),
      disabledBorderColor: color(
        'disabledBorderColor',
        fallback.disabledBorderColor,
      ),
      errorBorderColor: color('errorBorderColor', fallback.errorBorderColor),
      radius: number('radius', fallback.radius),
      borderWidth: number('borderWidth', fallback.borderWidth),
      horizontalPadding: number(
        'horizontalPadding',
        fallback.horizontalPadding,
      ),
      verticalPadding: number('verticalPadding', fallback.verticalPadding),
      dense: field<bool?>('dense', fallback.dense),
      prefixText: field('prefixText', fallback.prefixText),
      suffixText: field('suffixText', fallback.suffixText),
      prefixIcon: icon('prefixIcon', fallback.prefixIcon),
      suffixIcon: icon('suffixIcon', fallback.suffixIcon),
      suffix: choice(
        'suffix',
        TextFieldSuffix.values,
        fallback.suffix,
      ),
      helperText: field('helperText', fallback.helperText),
      errorText: field('errorText', fallback.errorText),
      showCounter: field('showCounter', fallback.showCounter),
      maxLength: field<int?>('maxLength', fallback.maxLength),
      filter: choice('filter', TextFieldFilter.values, fallback.filter),
      pattern: field('pattern', fallback.pattern),
      keyboard: choice(
        'keyboard',
        TextFieldKeyboard.values,
        fallback.keyboard,
      ),
      action: choice(
        'action',
        TextFieldAction.values,
        fallback.action,
      ),
      capitalization: choice(
        'capitalization',
        TextCapitalization.values,
        fallback.capitalization,
      ),
      verticalAlign: choice(
        'verticalAlign',
        TextFieldVerticalAlign.values,
        fallback.verticalAlign,
      ),
      floatingLabel: !json.containsKey('floatingLabel')
          ? fallback.floatingLabel
          : json['floatingLabel'] == null
          ? null
          : choice(
              'floatingLabel',
              FloatingLabelBehavior.values,
              FloatingLabelBehavior.auto,
            ),
      autocorrect: field('autocorrect', fallback.autocorrect),
      suggestions: field('suggestions', fallback.suggestions),
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
