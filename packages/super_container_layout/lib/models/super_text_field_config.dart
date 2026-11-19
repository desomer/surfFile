/// Configuration ([SuperTextFieldConfig]) du composant de champ de saisie [SuperTextField].
///
/// Regroupe les options de variante visuelle, de filtrage de saisie, de clavier,
/// d'alignement et de style typographique d'un champ texte.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import 'json_syntax.dart';
import 'material_icon_catalog.dart';
import 'text_field_constraints.dart';

export 'text_field_constraints.dart'
    show TextFieldFormat, TextFieldValueType;

/// Style de bordure et de remplissage d'un [SuperTextField].
enum TextFieldVariant { theme, filled, outlined, underline, borderless }

/// Filtre de caractères appliqué à la saisie d'un [SuperTextField].
enum TextFieldFilter { none, digits, decimal, letters, pattern }

/// Comportement du bouton suffixe affiché dans un [SuperTextField].
enum TextFieldSuffix { decoration, clear, visibility }

/// Type de clavier virtuel associé à un [SuperTextField].
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

/// Action du bouton de validation du clavier (`TextInputAction`) d'un [SuperTextField].
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

/// Alignement vertical du texte dans un [SuperTextField].
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
  // Ces noms sont des identifiants JSON publics et doivent rester inchangés.
  // ignore: constant_identifier_names
  location_on(Icons.location_on_outlined),
  // ignore: constant_identifier_names
  credit_card(Icons.credit_card_outlined),
  payments(Icons.payments_outlined),
  work(Icons.work_outline),
  folder(Icons.folder_outlined),
  description(Icons.description_outlined),
  // ignore: constant_identifier_names
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
  // ignore: constant_identifier_names
  alternate_email(Icons.alternate_email),
  // ignore: constant_identifier_names
  qr_code(Icons.qr_code_2),
  code(Icons.code),
  // ignore: constant_identifier_names
  filter_list(Icons.filter_list),
  tune(Icons.tune),
  // ignore: constant_identifier_names
  shopping_cart(Icons.shopping_cart_outlined),
  inventory(Icons.inventory_2_outlined),
  // ignore: constant_identifier_names
  local_shipping(Icons.local_shipping_outlined);

  const TextFieldIcon(this.data);
  final IconData data;

  String get displayLabel => MaterialIconCatalog.labelOf(name);
}

/// Modèle immuable de configuration d'un composant [SuperTextField].
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
    this.mask = '',
    this.maskIncludeLiterals = false,
    this.decimalDigits,
    this.decimalSeparator = '.',
    this.thousandsSeparator = '',
    this.dateFormat = '',
    this.valueType = TextFieldValueType.string,
    this.required = false,
    this.minLength,
    this.validationPattern = '',
    this.format = TextFieldFormat.none,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
    this.enumValues = const [],
    this.constValue,
    this.validationMessage = '',
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

  /// Masque à motifs appliqué à la saisie et à l'affichage (`#`, `A`, `U`, `L`, `*`).
  final String mask;

  /// Inclut les littéraux du masque dans la valeur stockée/validée lorsque `true`.
  final bool maskIncludeLiterals;

  /// Nombre de décimales fixes à l'affichage numérique (hors focus / mode `display`).
  final int? decimalDigits;

  /// Séparateur décimal utilisé pour l'affichage et la saisie (`.` ou `,`).
  final String decimalSeparator;

  /// Séparateur des milliers utilisé pour l'affichage numérique (`''`, `' '`, `','`, `'.'`…).
  final String thousandsSeparator;

  /// Motif `DateFormat` (`intl`) convertissant entre stockage ISO et affichage.
  final String dateFormat;

  /// Type JSON Schema de la valeur (`string`, `integer`, `number`).
  final TextFieldValueType valueType;

  /// Contrainte JSON Schema `required` (champ non vide obligatoire).
  final bool required;

  /// Contrainte JSON Schema `minLength` (en graphèmes).
  final int? minLength;

  /// Contrainte JSON Schema `pattern` (expression régulière sur la valeur).
  final String validationPattern;

  /// Contrainte JSON Schema `format` (`email`, `uri`, `uuid`, `date`, etc.).
  final TextFieldFormat format;

  /// Contrainte JSON Schema `minimum` (borne inférieure incluse).
  final double? minimum;

  /// Contrainte JSON Schema `maximum` (borne supérieure incluse).
  final double? maximum;

  /// Contrainte JSON Schema `exclusiveMinimum` (borne inférieure stricte).
  final double? exclusiveMinimum;

  /// Contrainte JSON Schema `exclusiveMaximum` (borne supérieure stricte).
  final double? exclusiveMaximum;

  /// Contrainte JSON Schema `multipleOf` (diviseur strictement positif).
  final double? multipleOf;

  /// Contrainte JSON Schema `enum` (liste des valeurs autorisées).
  final List<String> enumValues;

  /// Contrainte JSON Schema `const` (valeur exacte imposée).
  final String? constValue;

  /// Message d'erreur personnalisé affiché lorsqu'une contrainte échoue.
  final String validationMessage;

  /// Vrai si un formatage numérique (décimales ou séparateurs) est actif.
  bool get hasNumericFormatting =>
      decimalDigits != null ||
      thousandsSeparator.isNotEmpty ||
      decimalSeparator != '.';

  /// Vrai si au moins une contrainte numérique JSON Schema est définie.
  bool get hasNumericConstraints =>
      minimum != null ||
      maximum != null ||
      exclusiveMinimum != null ||
      exclusiveMaximum != null ||
      multipleOf != null;

  /// Vrai si un masque de saisie/affichage ou formatage de date/nombre est actif.
  bool get hasMaskOrFormat =>
      mask.isNotEmpty || dateFormat.isNotEmpty || hasNumericFormatting;

  /// Vrai si au moins une contrainte de validation JSON Schema est active.
  bool get hasConstraints =>
      required ||
      minLength != null ||
      maxLength != null ||
      valueType != TextFieldValueType.string ||
      hasNumericConstraints ||
      validationPattern.isNotEmpty ||
      format != TextFieldFormat.none ||
      enumValues.isNotEmpty ||
      constValue != null ||
      mask.isNotEmpty ||
      dateFormat.isNotEmpty;

  /// Transforme une valeur stockée (brute / ISO / canonique) en texte d'affichage.
  String toDisplayText(String storageText, {bool focused = false}) {
    if (storageText.isEmpty) return '';
    var text = storageText;
    if (dateFormat.isNotEmpty) {
      text = DateFieldFormat.formatDisplay(text, dateFormat);
    }
    if (mask.isNotEmpty) {
      return PatternMask(mask).format(text);
    }
    if (dateFormat.isEmpty && hasNumericFormatting) {
      return NumberFieldFormat.formatDisplay(
        text,
        decimalDigits: decimalDigits,
        decimalSeparator: decimalSeparator,
        thousandsSeparator: thousandsSeparator,
        focused: focused,
      );
    }
    return text;
  }

  /// Transforme un texte saisi/affiché en valeur brute destinée au stockage et
  /// à la validation JSON Schema.
  String toStorageText(String displayText) {
    if (displayText.isEmpty) return '';
    var text = displayText;
    if (dateFormat.isNotEmpty) {
      final formatted = mask.isNotEmpty
          ? PatternMask(mask).format(text)
          : text;
      final iso = DateFieldFormat.tryToIso(
        formatted,
        dateFormat,
        forceDateTime: format == TextFieldFormat.dateTime,
      );
      if (iso != null) return iso;
      return mask.isNotEmpty && !maskIncludeLiterals
          ? PatternMask(mask).strip(text)
          : formatted;
    }
    if (mask.isNotEmpty) {
      final maskModel = PatternMask(mask);
      return maskIncludeLiterals
          ? maskModel.format(text)
          : maskModel.strip(text);
    }
    if (hasNumericFormatting || valueType != TextFieldValueType.string) {
      return NumberFieldFormat.toStorage(
        text,
        decimalSeparator: decimalSeparator,
        thousandsSeparator: thousandsSeparator,
      );
    }
    return text;
  }

  /// Valide [storageValue] (et éventuellement [displayValue]) selon les
  /// contraintes JSON Schema configurées. Retourne `null` si valide.
  String? validateValue(
    String storageValue, {
    String? displayValue,
    bool obscureText = false,
  }) => TextFieldConstraintValidator.validate(
    storageValue: storageValue,
    displayValue: displayValue,
    obscureText: obscureText,
    mask: mask,
    dateFormat: dateFormat,
    valueType: valueType,
    required: required,
    minLength: minLength,
    maxLength: maxLength,
    validationPattern: validationPattern,
    format: format,
    minimum: minimum,
    maximum: maximum,
    exclusiveMinimum: exclusiveMinimum,
    exclusiveMaximum: exclusiveMaximum,
    multipleOf: multipleOf,
    enumValues: enumValues,
    constValue: constValue,
    validationMessage: validationMessage,
    decimalSeparator: decimalSeparator,
    thousandsSeparator: thousandsSeparator,
  );

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
    if (minLength != null && minLength! < 0) {
      throw const FormatException(
        'La longueur minimale doit être positive ou nulle.',
      );
    }
    if (minLength != null && maxLength != null && minLength! > maxLength!) {
      throw const FormatException(
        'La longueur minimale doit être inférieure ou égale à la longueur maximale.',
      );
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
    if (validationPattern.isNotEmpty) {
      try {
        RegExp(validationPattern, unicode: true);
      } on FormatException {
        throw const FormatException(
          'Expression régulière de validation invalide.',
        );
      }
    }
    PatternMask.validatePattern(mask);
    DateFieldFormat.validatePattern(dateFormat);
    if (decimalDigits != null && (decimalDigits! < 0 || decimalDigits! > 10)) {
      throw const FormatException(
        'Le nombre de décimales doit être compris entre 0 et 10.',
      );
    }
    if (decimalSeparator != '.' && decimalSeparator != ',') {
      throw const FormatException(
        'Le séparateur décimal doit être "." ou ",".',
      );
    }
    if (thousandsSeparator.length > 1) {
      throw const FormatException(
        'Le séparateur des milliers doit contenir au plus un caractère.',
      );
    }
    if (thousandsSeparator.isNotEmpty &&
        thousandsSeparator == decimalSeparator) {
      throw const FormatException(
        'Le séparateur des milliers doit être différent du séparateur décimal.',
      );
    }
    for (final bound in [
      minimum,
      maximum,
      exclusiveMinimum,
      exclusiveMaximum,
      multipleOf,
    ]) {
      if (bound != null && !bound.isFinite) {
        throw const FormatException('Borne numérique invalide.');
      }
    }
    if (multipleOf != null && multipleOf! <= 0) {
      throw const FormatException(
        'Le pas multipleOf doit être strictement positif.',
      );
    }
    if (minimum != null && maximum != null && minimum! > maximum!) {
      throw const FormatException(
        'La borne minimum doit être inférieure ou égale à maximum.',
      );
    }
    if (exclusiveMinimum != null &&
        exclusiveMaximum != null &&
        exclusiveMinimum! >= exclusiveMaximum!) {
      throw const FormatException(
        'La borne exclusiveMinimum doit être strictement inférieure à exclusiveMaximum.',
      );
    }
    if (minimum != null &&
        exclusiveMaximum != null &&
        minimum! >= exclusiveMaximum!) {
      throw const FormatException(
        'La borne minimum doit être strictement inférieure à exclusiveMaximum.',
      );
    }
    if (exclusiveMinimum != null &&
        maximum != null &&
        exclusiveMinimum! >= maximum!) {
      throw const FormatException(
        'La borne exclusiveMinimum doit être strictement inférieure à maximum.',
      );
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
    if (obscureText && hasMaskOrFormat) {
      throw const FormatException(
        'Un mot de passe ne peut pas utiliser un masque de saisie ou un formatage.',
      );
    }
    if (maxLines > 1 && hasMaskOrFormat) {
      throw const FormatException(
        'Un champ multiligne ne peut pas utiliser un masque de saisie ou un formatage.',
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
    String? mask,
    bool? maskIncludeLiterals,
    int? decimalDigits,
    String? decimalSeparator,
    String? thousandsSeparator,
    String? dateFormat,
    TextFieldValueType? valueType,
    bool? required,
    int? minLength,
    String? validationPattern,
    TextFieldFormat? format,
    double? minimum,
    double? maximum,
    double? exclusiveMinimum,
    double? exclusiveMaximum,
    double? multipleOf,
    List<String>? enumValues,
    String? constValue,
    String? validationMessage,
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
    bool clearDecimalDigits = false,
    bool clearMinLength = false,
    bool clearMinimum = false,
    bool clearMaximum = false,
    bool clearExclusiveMinimum = false,
    bool clearExclusiveMaximum = false,
    bool clearMultipleOf = false,
    bool clearConstValue = false,
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
    mask: mask ?? this.mask,
    maskIncludeLiterals: maskIncludeLiterals ?? this.maskIncludeLiterals,
    decimalDigits: clearDecimalDigits
        ? null
        : decimalDigits ?? this.decimalDigits,
    decimalSeparator: decimalSeparator ?? this.decimalSeparator,
    thousandsSeparator: thousandsSeparator ?? this.thousandsSeparator,
    dateFormat: dateFormat ?? this.dateFormat,
    valueType: valueType ?? this.valueType,
    required: required ?? this.required,
    minLength: clearMinLength ? null : minLength ?? this.minLength,
    validationPattern: validationPattern ?? this.validationPattern,
    format: format ?? this.format,
    minimum: clearMinimum ? null : minimum ?? this.minimum,
    maximum: clearMaximum ? null : maximum ?? this.maximum,
    exclusiveMinimum: clearExclusiveMinimum
        ? null
        : exclusiveMinimum ?? this.exclusiveMinimum,
    exclusiveMaximum: clearExclusiveMaximum
        ? null
        : exclusiveMaximum ?? this.exclusiveMaximum,
    multipleOf: clearMultipleOf ? null : multipleOf ?? this.multipleOf,
    enumValues: enumValues != null
        ? List.unmodifiable(enumValues)
        : this.enumValues,
    constValue: clearConstValue ? null : constValue ?? this.constValue,
    validationMessage: validationMessage ?? this.validationMessage,
  );

  Map<String, Object?> toJson() => {
    'variant': variant.name,
    'fillColor': JsonColor.toJsonNullable(fillColor),
    'focusFillColor': JsonColor.toJsonNullable(focusFillColor),
    'disabledFillColor': JsonColor.toJsonNullable(disabledFillColor),
    'errorFillColor': JsonColor.toJsonNullable(errorFillColor),
    'borderColor': JsonColor.toJsonNullable(borderColor),
    'focusBorderColor': JsonColor.toJsonNullable(focusBorderColor),
    'disabledBorderColor': JsonColor.toJsonNullable(disabledBorderColor),
    'errorBorderColor': JsonColor.toJsonNullable(errorBorderColor),
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
    'mask': mask,
    'maskIncludeLiterals': maskIncludeLiterals,
    'decimalDigits': decimalDigits,
    'decimalSeparator': decimalSeparator,
    'thousandsSeparator': thousandsSeparator,
    'dateFormat': dateFormat,
    'valueType': valueType.name,
    'required': required,
    'minLength': minLength,
    'validationPattern': validationPattern,
    'format': format.name,
    'minimum': minimum,
    'maximum': maximum,
    'exclusiveMinimum': exclusiveMinimum,
    'exclusiveMaximum': exclusiveMaximum,
    'multipleOf': multipleOf,
    'enumValues': List<String>.unmodifiable(enumValues),
    'constValue': constValue,
    'validationMessage': validationMessage,
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
      if (mask.isNotEmpty) 'mask': mask,
      if (maskIncludeLiterals != d.maskIncludeLiterals)
        'maskIncludeLiterals': maskIncludeLiterals,
      if (decimalDigits != null) 'decimalDigits': decimalDigits,
      if (decimalSeparator != d.decimalSeparator)
        'decimalSeparator': decimalSeparator,
      if (thousandsSeparator.isNotEmpty)
        'thousandsSeparator': thousandsSeparator,
      if (dateFormat.isNotEmpty) 'dateFormat': dateFormat,
      if (valueType != d.valueType) 'valueType': valueType.name,
      if (required != d.required) 'required': required,
      if (minLength != null) 'minLength': minLength,
      if (validationPattern.isNotEmpty)
        'validationPattern': validationPattern,
      if (format != d.format) 'format': format.schemaName,
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (exclusiveMinimum != null) 'exclusiveMinimum': exclusiveMinimum,
      if (exclusiveMaximum != null) 'exclusiveMaximum': exclusiveMaximum,
      if (multipleOf != null) 'multipleOf': multipleOf,
      if (enumValues.isNotEmpty)
        'enumValues': List<String>.unmodifiable(enumValues),
      if (constValue != null) 'constValue': constValue,
      if (validationMessage.isNotEmpty)
        'validationMessage': validationMessage,
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

    double? signedNumber(String key, double? defaultNum) {
      if (!json.containsKey(key)) return defaultNum;
      final value = json[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite) {
        throw FormatException('Borne numérique invalide : $key.');
      }
      return value.toDouble();
    }

    TextFieldFormat parseFormat(String key, TextFieldFormat fallbackVal) {
      if (!json.containsKey(key)) return fallbackVal;
      final raw = json[key];
      if (raw is! String) {
        throw FormatException('Option de champ invalide : $key.');
      }
      final parsed = TextFieldFormat.tryParse(raw);
      if (parsed == null) {
        throw FormatException('Option de champ invalide : $key.');
      }
      return parsed;
    }

    List<String> parseEnumValues(String key, List<String> fallbackVal) {
      if (!json.containsKey(key)) return fallbackVal;
      final raw = json[key];
      if (raw is! List) {
        throw FormatException('Option de champ invalide : $key.');
      }
      final items = <String>[];
      for (final item in raw) {
        if (item is! String && item is! num && item is! bool) {
          throw FormatException('Option de champ invalide : $key.');
        }
        items.add(item.toString());
      }
      return List<String>.unmodifiable(items);
    }

    TextFieldIcon? icon(String key, TextFieldIcon? defaultIcon) {
      if (!json.containsKey(key)) return defaultIcon;
      final raw = json[key];
      if (raw == null) return null;
      if (raw is! String) {
        throw FormatException('Option de champ invalide : $key.');
      }
      var normalized = raw.trim().toLowerCase();
      for (final suffix in const [
        '_outlined',
        '_outline',
        '_rounded',
        '_sharp',
        '_filled',
        '_border',
      ]) {
        if (normalized.endsWith(suffix) && normalized.length > suffix.length) {
          normalized = normalized.substring(
            0,
            normalized.length - suffix.length,
          );
          break;
        }
      }
      const aliases = <String, TextFieldIcon>{
        'calendar_today': TextFieldIcon.calendar,
        'calendar_month': TextFieldIcon.calendar,
        'event': TextFieldIcon.calendar,
        'event_note': TextFieldIcon.calendar,
        'today': TextFieldIcon.calendar,
        'date_range': TextFieldIcon.calendar,
        'business': TextFieldIcon.work,
        'business_center': TextFieldIcon.work,
        'apartment': TextFieldIcon.work,
        'domain': TextFieldIcon.work,
        'corporate_fare': TextFieldIcon.work,
        'store': TextFieldIcon.work,
        'storefront': TextFieldIcon.work,
        'mail': TextFieldIcon.email,
        'contact_mail': TextFieldIcon.email,
        'call': TextFieldIcon.phone,
        'contact_phone': TextFieldIcon.phone,
        'phone_in_talk': TextFieldIcon.phone,
        'smartphone': TextFieldIcon.phone,
        'place': TextFieldIcon.location_on,
        'pin_drop': TextFieldIcon.location_on,
        'location_city': TextFieldIcon.location_on,
        'map': TextFieldIcon.location_on,
        'euro': TextFieldIcon.payments,
        'attach_money': TextFieldIcon.payments,
        'monetization_on': TextFieldIcon.payments,
        'paid': TextFieldIcon.payments,
        'account_balance': TextFieldIcon.payments,
        'savings': TextFieldIcon.payments,
        'receipt': TextFieldIcon.description,
        'receipt_long': TextFieldIcon.description,
        'request_quote': TextFieldIcon.description,
        'article': TextFieldIcon.description,
        'notes': TextFieldIcon.description,
        'assignment': TextFieldIcon.description,
        'account_circle': TextFieldIcon.person,
        'contacts': TextFieldIcon.person,
        'contact_page': TextFieldIcon.person,
        'people': TextFieldIcon.group,
        'groups': TextFieldIcon.group,
        'public': TextFieldIcon.language,
      };
      final resolved =
          TextFieldIcon.values.where((v) => v.name == normalized).firstOrNull ??
          aliases[normalized];
      if (resolved == null) {
        final allowed = TextFieldIcon.values.map((v) => v.name).join(', ');
        throw FormatException(
          'Option de champ invalide : $key ("$raw"). Icônes de champ autorisées : $allowed.',
        );
      }
      return resolved;
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
      mask: field('mask', fallback.mask),
      maskIncludeLiterals: field(
        'maskIncludeLiterals',
        fallback.maskIncludeLiterals,
      ),
      decimalDigits: field<int?>('decimalDigits', fallback.decimalDigits),
      decimalSeparator: field('decimalSeparator', fallback.decimalSeparator),
      thousandsSeparator: field(
        'thousandsSeparator',
        fallback.thousandsSeparator,
      ),
      dateFormat: field('dateFormat', fallback.dateFormat),
      valueType: choice(
        'valueType',
        TextFieldValueType.values,
        fallback.valueType,
      ),
      required: field('required', fallback.required),
      minLength: field<int?>('minLength', fallback.minLength),
      validationPattern: field('validationPattern', fallback.validationPattern),
      format: parseFormat('format', fallback.format),
      minimum: signedNumber('minimum', fallback.minimum),
      maximum: signedNumber('maximum', fallback.maximum),
      exclusiveMinimum: signedNumber(
        'exclusiveMinimum',
        fallback.exclusiveMinimum,
      ),
      exclusiveMaximum: signedNumber(
        'exclusiveMaximum',
        fallback.exclusiveMaximum,
      ),
      multipleOf: signedNumber('multipleOf', fallback.multipleOf),
      enumValues: parseEnumValues('enumValues', fallback.enumValues),
      constValue: field<String?>('constValue', fallback.constValue),
      validationMessage: field('validationMessage', fallback.validationMessage),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperTextFieldConfig && _equal(toJson(), other.toJson());
  static bool _equal(Map<String, Object?> a, Map<String, Object?> b) =>
      a.length == b.length &&
      a.entries.every((entry) {
        final otherVal = b[entry.key];
        final selfVal = entry.value;
        if (selfVal is List && otherVal is List) {
          return listEquals(selfVal, otherVal);
        }
        return selfVal == otherVal;
      });
  @override
  int get hashCode => Object.hashAll(
    toJson().values.map((v) => v is List ? Object.hashAll(v) : v),
  );
}
