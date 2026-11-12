/// Configuration ([SuperChoiceConfig]) du composant de sélection [SuperChoice].
///
/// Regroupe les variantes de contrôles de choix (`SegmentedButton`, `DropdownButton`,
/// `RadioListTile`, `FilterChip`, `CheckboxListTile`, `SearchAnchor`), la liste
/// d'options statiques ([SuperChoiceOption]) ou dynamiques liées à un tableau
/// de repository JSON ([optionsBinding]), ainsi que le style visuel.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import 'json_syntax.dart';
import 'json_text_binding.dart';
import 'material_icon_catalog.dart';

/// Type de contrôle de choix rendu par [SuperChoice].
enum ChoiceVariant {
  /// 2 à 5 choix uniques via `SegmentedButton`.
  segmented,

  /// Choix unique compact via `DropdownButtonFormField`.
  dropdown,

  /// Choix unique visible via `RadioListTile`.
  radio,

  /// Plusieurs choix sous forme de puces via `FilterChip`.
  filterChip,

  /// Plusieurs choix sous forme de liste via `CheckboxListTile`.
  checkboxList,

  /// Grande liste recherchable via `SearchAnchor`.
  searchAnchor;

  /// Indique si cette variante autorise la sélection de plusieurs valeurs.
  bool get isMultiple =>
      this == ChoiceVariant.filterChip || this == ChoiceVariant.checkboxList;

  /// Indique si cette variante ne sélectionne qu'une seule valeur à la fois.
  bool get isSingle => !isMultiple;

  /// Libellé lisible dans les éditeurs.
  String get displayLabel => switch (this) {
    ChoiceVariant.segmented => 'SegmentedButton (2 à 5 choix)',
    ChoiceVariant.dropdown => 'DropdownButton (compact)',
    ChoiceVariant.radio => 'RadioListTile (choix visibles)',
    ChoiceVariant.filterChip => 'FilterChip (choix multiples)',
    ChoiceVariant.checkboxList => 'CheckboxListTile (choix multiples)',
    ChoiceVariant.searchAnchor => 'SearchAnchor (liste recherchable)',
  };

  /// Libellé court pour les barres segmentées ou résumés.
  String get shortLabel => switch (this) {
    ChoiceVariant.segmented => 'Segments',
    ChoiceVariant.dropdown => 'Dropdown',
    ChoiceVariant.radio => 'Radio',
    ChoiceVariant.filterChip => 'Chips',
    ChoiceVariant.checkboxList => 'Checkboxes',
    ChoiceVariant.searchAnchor => 'Recherche',
  };
}

/// Option élémentaire d'un composant [SuperChoice].
@immutable
class SuperChoiceOption {
  const SuperChoiceOption({
    required this.value,
    this.label = '',
    this.icon,
  });

  /// Valeur technique stockée lorsque l'option est sélectionnée.
  final String value;

  /// Libellé affiché à l'utilisateur (repli sur [value] s'il est vide).
  final String label;

  /// Identifiant optionnel d'icône Material issue de [MaterialIconCatalog].
  final String? icon;

  /// Libellé effectivement affiché (`label` si non vide, sinon `value`).
  String get effectiveLabel => label.trim().isEmpty ? value : label;

  /// Données d'icône Material résolues si [icon] est renseigné et valide.
  IconData? get iconData => icon != null && MaterialIconCatalog.isKnown(icon!)
      ? MaterialIconCatalog.resolve(icon!)
      : null;

  /// Valide les invariants de l'option.
  void validate() {
    if (value.trim().isEmpty) {
      throw const FormatException(
        'Chaque option de choix doit avoir une valeur non vide.',
      );
    }
    if (value.contains(',')) {
      throw const FormatException(
        'La valeur d’une option ne peut pas contenir de virgule.',
      );
    }
    if (icon != null &&
        (icon!.trim().isEmpty || !MaterialIconCatalog.isKnown(icon!))) {
      throw FormatException('Icône d’option inconnue : $icon.');
    }
  }

  /// Retourne une copie modifiée de cette option.
  SuperChoiceOption copyWith({
    String? value,
    String? label,
    String? icon,
    bool clearIcon = false,
  }) => SuperChoiceOption(
    value: value ?? this.value,
    label: label ?? this.label,
    icon: clearIcon ? null : icon ?? this.icon,
  );

  /// Sérialise l'option en Map JSON.
  Map<String, Object?> toJson() {
    validate();
    return {
      'value': value,
      if (label.isNotEmpty) 'label': label,
      if (icon != null) 'icon': icon,
    };
  }

  /// Sérialise l'option au format compact (simple chaîne si sans label ni icône).
  Object toCompactJson() {
    validate();
    if (label.isEmpty && icon == null) return value;
    return toJson();
  }

  /// Désérialise une option depuis une chaîne ou une Map JSON.
  factory SuperChoiceOption.fromJson(Object? json) {
    if (json is String) {
      final option = SuperChoiceOption(value: json.trim());
      option.validate();
      return option;
    }
    if (json is num || json is bool) {
      final option = SuperChoiceOption(value: json.toString());
      option.validate();
      return option;
    }
    if (json is! Map) {
      throw const FormatException('Option de choix invalide.');
    }
    const allowedKeys = {'value', 'id', 'label', 'icon'};
    if (json.keys.any((k) => !allowedKeys.contains(k))) {
      throw const FormatException('Propriété d’option de choix inconnue.');
    }
    final rawValue = json.containsKey('value') ? json['value'] : json['id'];
    final String value;
    if (rawValue is String) {
      value = rawValue;
    } else if (rawValue is num || rawValue is bool) {
      value = rawValue.toString();
    } else {
      throw const FormatException('Valeur d’option de choix invalide.');
    }
    final rawLabel = json['label'];
    if (rawLabel != null && rawLabel is! String) {
      throw const FormatException('Libellé d’option de choix invalide.');
    }
    final rawIcon = json['icon'];
    if (rawIcon != null && rawIcon is! String) {
      throw const FormatException('Icône d’option de choix invalide.');
    }
    final option = SuperChoiceOption(
      value: value,
      label: rawLabel ?? '',
      icon: rawIcon?.trim().isEmpty == true ? null : rawIcon,
    );
    option.validate();
    return option;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperChoiceOption &&
      value == other.value &&
      label == other.label &&
      icon == other.icon;

  @override
  int get hashCode => Object.hash(value, label, icon);
}

/// Alias orthographique demandé (`SuperChoiseOption`).
typedef SuperChoiseOption = SuperChoiceOption;

/// Modèle immuable de configuration d'un composant [SuperChoice].
@immutable
class SuperChoiceConfig {
  const SuperChoiceConfig({
    this.variant = ChoiceVariant.dropdown,
    this.options = const [],
    this.optionsBinding,
    this.optionValueKey = '',
    this.optionLabelKey = '',
    this.optionIconKey = '',
    this.allowEmpty = false,
    this.dense,
    this.direction = Axis.vertical,
    this.spacing = 8.0,
    this.showCheckmark = true,
    this.searchHint = '',
    this.helperText = '',
    this.errorText = '',
    this.fillColor,
    this.selectedColor,
    this.borderColor,
    this.radius,
    this.borderWidth,
  });

  /// Type de composant de sélection à afficher.
  final ChoiceVariant variant;

  /// Liste statique des options disponibles (utilisée quand [optionsBinding] est nul).
  final List<SuperChoiceOption> options;

  /// Liaison optionnelle vers un tableau JSON fournissant dynamiquement les options.
  final JsonTextBinding? optionsBinding;

  /// Clé de valeur dans chaque objet du tableau lié (ex: `id` ou `code`).
  final String optionValueKey;

  /// Clé de libellé dans chaque objet du tableau lié (ex: `label` ou `nom`).
  final String optionLabelKey;

  /// Clé d'icône dans chaque objet du tableau lié (ex: `icon`).
  final String optionIconKey;

  /// Autorise l'absence ou l'effacement de sélection en mode choix unique.
  final bool allowEmpty;

  /// Densité visuelle compacte (`true`), confortable (`false`) ou héritée (`null`).
  final bool? dense;

  /// Orientation de disposition pour `radio`, `checkboxList` et `filterChip`.
  final Axis direction;

  /// Espacement en pixels entre les puces ou options.
  final double spacing;

  /// Affiche une coche sur les options sélectionnées (`SegmentedButton`, `FilterChip`).
  final bool showCheckmark;

  /// Texte indicatif dans le champ de recherche (`SearchAnchor`).
  final String searchHint;

  /// Texte d'aide affiché sous le composant.
  final String helperText;

  /// Message d'erreur manuel affiché sous le composant.
  final String errorText;

  /// Couleur de fond du contrôle ou des puces non sélectionnées.
  final Color? fillColor;

  /// Couleur d'accentuation / remplissage des éléments sélectionnés.
  final Color? selectedColor;

  /// Couleur de bordure du contrôle ou des puces.
  final Color? borderColor;

  /// Rayon d'arrondi de la bordure ou des puces.
  final double? radius;

  /// Épaisseur de la bordure.
  final double? borderWidth;

  /// Options par défaut utilisées en aperçu ou lorsqu'aucune option n'est définie.
  static const List<SuperChoiceOption> defaultFallbackOptions = [
    SuperChoiceOption(value: 'option_1', label: 'Option 1'),
    SuperChoiceOption(value: 'option_2', label: 'Option 2'),
  ];

  /// Découpe une chaîne CSV (ex: `"opt1,opt2"`) en liste de valeurs uniques non vides.
  static List<String> parseSelectedValues(String raw) {
    if (raw.trim().isEmpty) return const [];
    final seen = <String>{};
    final result = <String>[];
    for (final part in raw.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return List.unmodifiable(result);
  }

  /// Encode un ensemble de valeurs sélectionnées en chaîne CSV sans doublons.
  static String encodeSelectedValues(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result.join(',');
  }

  /// Extrait une liste de [SuperChoiceOption] depuis un tableau JSON de repository.
  List<SuperChoiceOption> extractOptionsFromJsonArray(List<Object?> items) {
    final extracted = <SuperChoiceOption>[];
    final seen = <String>{};
    for (final item in items) {
      if (item == null) continue;
      String? val;
      String lbl = '';
      String? ico;
      if (item is String || item is num || item is bool) {
        val = item.toString().trim();
      } else if (item is Map) {
        Object? rawVal;
        if (optionValueKey.trim().isNotEmpty) {
          rawVal = item[optionValueKey.trim()];
        } else {
          rawVal =
              item['value'] ??
              item['id'] ??
              item['code'] ??
              item['key'] ??
              item.values.firstOrNull;
        }
        if (rawVal is String || rawVal is num || rawVal is bool) {
          val = rawVal.toString().trim();
        }
        Object? rawLbl;
        if (optionLabelKey.trim().isNotEmpty) {
          rawLbl = item[optionLabelKey.trim()];
        } else {
          rawLbl =
              item['label'] ??
              item['name'] ??
              item['nom'] ??
              item['title'] ??
              item['text'];
        }
        if (rawLbl is String || rawLbl is num || rawLbl is bool) {
          lbl = rawLbl.toString();
        }
        Object? rawIco;
        if (optionIconKey.trim().isNotEmpty) {
          rawIco = item[optionIconKey.trim()];
        } else if (item['icon'] is String) {
          rawIco = item['icon'];
        }
        if (rawIco is String && MaterialIconCatalog.isKnown(rawIco.trim())) {
          ico = rawIco.trim();
        }
      }
      if (val != null &&
          val.isNotEmpty &&
          !val.contains(',') &&
          seen.add(val)) {
        extracted.add(
          SuperChoiceOption(
            value: val,
            label: lbl == val ? '' : lbl,
            icon: ico,
          ),
        );
      }
    }
    return List.unmodifiable(extracted);
  }

  /// Valide la cohérence de la configuration de choix.
  void validate() {
    optionsBinding?.validate();
    for (final value in [spacing, radius, borderWidth]) {
      if (value != null && (!value.isFinite || value < 0)) {
        throw const FormatException('Dimensions de choix invalides.');
      }
    }
    final seenValues = <String>{};
    for (final option in options) {
      option.validate();
      if (!seenValues.add(option.value)) {
        throw FormatException(
          'Valeur d’option dupliquée : ${option.value}.',
        );
      }
    }
    if (variant == ChoiceVariant.segmented &&
        optionsBinding == null &&
        options.isNotEmpty &&
        (options.length < 2 || options.length > 5)) {
      throw const FormatException(
        'SegmentedButton requiert entre 2 et 5 options.',
      );
    }
  }

  /// Crée une copie modifiée de cette configuration.
  SuperChoiceConfig copyWith({
    ChoiceVariant? variant,
    List<SuperChoiceOption>? options,
    JsonTextBinding? optionsBinding,
    bool clearOptionsBinding = false,
    String? optionValueKey,
    String? optionLabelKey,
    String? optionIconKey,
    bool? allowEmpty,
    bool? dense,
    bool inheritDense = false,
    Axis? direction,
    double? spacing,
    bool? showCheckmark,
    String? searchHint,
    String? helperText,
    String? errorText,
    Color? fillColor,
    bool inheritFillColor = false,
    Color? selectedColor,
    bool inheritSelectedColor = false,
    Color? borderColor,
    bool inheritBorderColor = false,
    double? radius,
    bool inheritRadius = false,
    double? borderWidth,
    bool inheritBorderWidth = false,
  }) => SuperChoiceConfig(
    variant: variant ?? this.variant,
    options: options != null ? List.unmodifiable(options) : this.options,
    optionsBinding: clearOptionsBinding
        ? null
        : optionsBinding ?? this.optionsBinding,
    optionValueKey: optionValueKey ?? this.optionValueKey,
    optionLabelKey: optionLabelKey ?? this.optionLabelKey,
    optionIconKey: optionIconKey ?? this.optionIconKey,
    allowEmpty: allowEmpty ?? this.allowEmpty,
    dense: inheritDense ? null : dense ?? this.dense,
    direction: direction ?? this.direction,
    spacing: spacing ?? this.spacing,
    showCheckmark: showCheckmark ?? this.showCheckmark,
    searchHint: searchHint ?? this.searchHint,
    helperText: helperText ?? this.helperText,
    errorText: errorText ?? this.errorText,
    fillColor: inheritFillColor ? null : fillColor ?? this.fillColor,
    selectedColor: inheritSelectedColor
        ? null
        : selectedColor ?? this.selectedColor,
    borderColor: inheritBorderColor ? null : borderColor ?? this.borderColor,
    radius: inheritRadius ? null : radius ?? this.radius,
    borderWidth: inheritBorderWidth ? null : borderWidth ?? this.borderWidth,
  );

  /// Sérialise la configuration complète en Map JSON.
  Map<String, Object?> toJson() {
    validate();
    return {
      'variant': variant.name,
      'options': [for (final option in options) option.toJson()],
      if (optionsBinding != null) 'optionsBinding': optionsBinding!.toJson(),
      'optionValueKey': optionValueKey,
      'optionLabelKey': optionLabelKey,
      'optionIconKey': optionIconKey,
      'allowEmpty': allowEmpty,
      'dense': dense,
      'direction': direction.name,
      'spacing': spacing,
      'showCheckmark': showCheckmark,
      'searchHint': searchHint,
      'helperText': helperText,
      'errorText': errorText,
      'fillColor': JsonColor.toJsonNullable(fillColor),
      'selectedColor': JsonColor.toJsonNullable(selectedColor),
      'borderColor': JsonColor.toJsonNullable(borderColor),
      'radius': radius,
      'borderWidth': borderWidth,
    };
  }

  /// Sérialise la configuration au format compact en omettant les valeurs par défaut.
  Map<String, Object?> toCompactJson() {
    validate();
    const d = SuperChoiceConfig();
    return {
      if (variant != d.variant) 'variant': variant.name,
      if (options.isNotEmpty)
        'options': [for (final option in options) option.toCompactJson()],
      if (optionsBinding != null)
        'optionsBinding': optionsBinding!.toCompactJson(),
      if (optionValueKey.isNotEmpty) 'optionValueKey': optionValueKey,
      if (optionLabelKey.isNotEmpty) 'optionLabelKey': optionLabelKey,
      if (optionIconKey.isNotEmpty) 'optionIconKey': optionIconKey,
      if (allowEmpty != d.allowEmpty) 'allowEmpty': allowEmpty,
      if (dense != null) 'dense': dense,
      if (direction != d.direction) 'direction': direction.name,
      if (spacing != d.spacing) 'spacing': spacing,
      if (showCheckmark != d.showCheckmark) 'showCheckmark': showCheckmark,
      if (searchHint.isNotEmpty) 'searchHint': searchHint,
      if (helperText.isNotEmpty) 'helperText': helperText,
      if (errorText.isNotEmpty) 'errorText': errorText,
      if (fillColor != null) 'fillColor': JsonColor.toHex(fillColor!),
      if (selectedColor != null)
        'selectedColor': JsonColor.toHex(selectedColor!),
      if (borderColor != null) 'borderColor': JsonColor.toHex(borderColor!),
      if (radius != null) 'radius': radius,
      if (borderWidth != null) 'borderWidth': borderWidth,
    };
  }

  static const Map<String, ChoiceVariant> _variantAliases = {
    'segmentedButton': ChoiceVariant.segmented,
    'SegmentedButton': ChoiceVariant.segmented,
    'dropdownButton': ChoiceVariant.dropdown,
    'DropdownButton': ChoiceVariant.dropdown,
    'radioListTile': ChoiceVariant.radio,
    'RadioListTile': ChoiceVariant.radio,
    'FilterChip': ChoiceVariant.filterChip,
    'chips': ChoiceVariant.filterChip,
    'chip': ChoiceVariant.filterChip,
    'checkboxListTile': ChoiceVariant.checkboxList,
    'CheckboxListTile': ChoiceVariant.checkboxList,
    'checkboxes': ChoiceVariant.checkboxList,
    'SearchAnchor': ChoiceVariant.searchAnchor,
    'dropdown_search': ChoiceVariant.searchAnchor,
    'dropdownSearch': ChoiceVariant.searchAnchor,
    'search': ChoiceVariant.searchAnchor,
  };

  /// Désérialise une instance de [SuperChoiceConfig] depuis un objet JSON.
  factory SuperChoiceConfig.fromJson(
    Object? json, {
    SuperChoiceConfig fallback = const SuperChoiceConfig(),
  }) {
    if (json is! Map) {
      throw const FormatException('Options de choix invalides.');
    }
    const allowedKeys = {
      'variant',
      'options',
      'optionsBinding',
      'optionValueKey',
      'optionLabelKey',
      'optionIconKey',
      'allowEmpty',
      'dense',
      'direction',
      'spacing',
      'showCheckmark',
      'searchHint',
      'helperText',
      'errorText',
      'fillColor',
      'selectedColor',
      'borderColor',
      'radius',
      'borderWidth',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException('Option de choix inconnue.');
    }

    T field<T>(String key, T fallbackVal) =>
        JsonReader.field(json, key, fallbackVal, context: 'Choice');

    final variantName = field('variant', fallback.variant.name);
    final variant = JsonReader.enumByName(
      ChoiceVariant.values,
      variantName,
      _variantAliases,
    );
    if (variant == null) {
      throw const FormatException('Variante de choix invalide.');
    }

    final directionName = field('direction', fallback.direction.name);
    final direction = JsonReader.enumByName(Axis.values, directionName);
    if (direction == null) {
      throw const FormatException('Orientation de choix invalide.');
    }

    List<SuperChoiceOption> parsedOptions = fallback.options;
    if (json.containsKey('options')) {
      final rawOptions = json['options'];
      if (rawOptions is! List) {
        throw const FormatException('La liste des options est invalide.');
      }
      parsedOptions = List.unmodifiable([
        for (final item in rawOptions) SuperChoiceOption.fromJson(item),
      ]);
    }

    final optionsBinding = !json.containsKey('optionsBinding')
        ? fallback.optionsBinding
        : json['optionsBinding'] == null
        ? null
        : JsonTextBinding.fromJson(json['optionsBinding']);

    Color? color(String key, Color? defaultColor) => JsonReader.nullableColor(
      json,
      key,
      defaultColor,
      errorMessage: 'Couleur de choix invalide : $key.',
    );

    double? number(String key, double? defaultNum) => JsonReader.nullableDouble(
      json,
      key,
      defaultNum,
      context: 'Choice',
    );

    final spacing = number('spacing', fallback.spacing) ?? fallback.spacing;

    final result = SuperChoiceConfig(
      variant: variant,
      options: parsedOptions,
      optionsBinding: optionsBinding,
      optionValueKey: field('optionValueKey', fallback.optionValueKey),
      optionLabelKey: field('optionLabelKey', fallback.optionLabelKey),
      optionIconKey: field('optionIconKey', fallback.optionIconKey),
      allowEmpty: field('allowEmpty', fallback.allowEmpty),
      dense: field<bool?>('dense', fallback.dense),
      direction: direction,
      spacing: spacing,
      showCheckmark: field('showCheckmark', fallback.showCheckmark),
      searchHint: field('searchHint', fallback.searchHint),
      helperText: field('helperText', fallback.helperText),
      errorText: field('errorText', fallback.errorText),
      fillColor: color('fillColor', fallback.fillColor),
      selectedColor: color('selectedColor', fallback.selectedColor),
      borderColor: color('borderColor', fallback.borderColor),
      radius: number('radius', fallback.radius),
      borderWidth: number('borderWidth', fallback.borderWidth),
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperChoiceConfig &&
      variant == other.variant &&
      listEquals(options, other.options) &&
      optionsBinding == other.optionsBinding &&
      optionValueKey == other.optionValueKey &&
      optionLabelKey == other.optionLabelKey &&
      optionIconKey == other.optionIconKey &&
      allowEmpty == other.allowEmpty &&
      dense == other.dense &&
      direction == other.direction &&
      spacing == other.spacing &&
      showCheckmark == other.showCheckmark &&
      searchHint == other.searchHint &&
      helperText == other.helperText &&
      errorText == other.errorText &&
      fillColor == other.fillColor &&
      selectedColor == other.selectedColor &&
      borderColor == other.borderColor &&
      radius == other.radius &&
      borderWidth == other.borderWidth;

  @override
  int get hashCode => Object.hash(
    variant,
    Object.hashAll(options),
    optionsBinding,
    optionValueKey,
    optionLabelKey,
    optionIconKey,
    allowEmpty,
    dense,
    direction,
    spacing,
    showCheckmark,
    searchHint,
    helperText,
    errorText,
    fillColor,
    selectedColor,
    borderColor,
    radius,
    borderWidth,
  );
}

/// Alias orthographique demandé (`SuperChoiseConfig`).
typedef SuperChoiseConfig = SuperChoiceConfig;
