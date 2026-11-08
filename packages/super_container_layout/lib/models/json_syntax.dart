/// Primitives de sérialisation et désérialisation JSON compactes (« AI-friendly »).
///
/// Fournit [JsonColor], [JsonComponentType], [JsonDimension], [JsonFontWeight],
/// [JsonSize] et [JsonPlacementEntry] pour convertir entre les raccourcis lisibles
/// utilisés par l'IA et les structures typées Flutter.
library;

import 'dart:ui' show Color, FontWeight, Size;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/painting.dart' show Axis, EdgeInsets;

import '../theme/container_style.dart';
import 'automatic_state.dart';
import 'component_config.dart';
import 'json_text_binding.dart';
import 'super_layout_config.dart'
    show
        SlotDimension,
        SlotPercentBasis,
        SlotSizeConstraints,
        SlotSizeUnit,
        ZoneFlowConfig;

/// Primitives de sérialisation et désérialisation JSON adaptées aux humains et aux IA.
abstract final class JsonColor {
  /// Formate une couleur en `#RRGGBB` (si opaque) ou `#AARRGGBB`.
  static String toHex(Color color) {
    final argb = color.toARGB32();
    final alpha = (argb >>> 24) & 0xFF;
    final rgb = argb & 0xFFFFFF;
    if (alpha == 0xFF) {
      return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
    }
    return '#${argb.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  static String? toHexNullable(Color? color) =>
      color == null ? null : toHex(color);

  /// Lit une couleur depuis une instance [Color], une chaîne hexadécimale
  /// (`#RRGGBB`, `#AARRGGBB`, `#RGB`, `#ARGB`, `0xAARRGGBB`) ou un entier ARGB 32 bits.
  static Color parse(Object? value, [String field = 'color']) {
    if (value is Color) {
      return value;
    }
    if (value is int && value >= 0 && value <= 0xFFFFFFFF) {
      return Color(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('#')) {
        final hex = trimmed.substring(1);
        if (_hexPattern.hasMatch(hex)) {
          if (hex.length == 3) {
            final r = int.parse(hex[0], radix: 16) * 17;
            final g = int.parse(hex[1], radix: 16) * 17;
            final b = int.parse(hex[2], radix: 16) * 17;
            return Color(0xFF000000 | (r << 16) | (g << 8) | b);
          }
          if (hex.length == 4) {
            final a = int.parse(hex[0], radix: 16) * 17;
            final r = int.parse(hex[1], radix: 16) * 17;
            final g = int.parse(hex[2], radix: 16) * 17;
            final b = int.parse(hex[3], radix: 16) * 17;
            return Color((a << 24) | (r << 16) | (g << 8) | b);
          }
          if (hex.length == 6) {
            return Color(0xFF000000 | int.parse(hex, radix: 16));
          }
          if (hex.length == 8) {
            return Color(int.parse(hex, radix: 16));
          }
        }
      } else if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
        final hex = trimmed.substring(2);
        if (_hexPattern.hasMatch(hex)) {
          if (hex.length == 6) {
            return Color(0xFF000000 | int.parse(hex, radix: 16));
          }
          if (hex.length == 8) {
            return Color(int.parse(hex, radix: 16));
          }
        }
      }
    }
    throw FormatException('Couleur invalide : $field.');
  }

  static Color? parseNullable(Object? value, [String field = 'color']) =>
      value == null ? null : parse(value, field);

  static final _hexPattern = RegExp(r'^[0-9a-fA-F]+$');
}

/// Normalisation des noms de composants entre la syntaxe courte IA et le Registry.
abstract final class JsonComponentType {
  static final Map<String, String> _aliases = {
    'Value': 'Value',
    'Renderer': 'Renderer',
    'SuperRenderer': 'Renderer',
    'Action': 'Action',
    'Button': 'Action',
    'Indicator': 'Indicator',
    'SuperIndicator': 'Indicator',
    'Icon': 'Indicator',
    'Separator': 'Separator',
    'SuperSeparator': 'Separator',
    'Divider': 'Separator',
    'Spacer': 'Separator',
    'Card': 'Card',
    'Layout': 'Layout',
    'ListView': 'ListView',
    'IterableContent': 'IterableContent',
    'ApplicationBar': 'ApplicationBar',
    'BottomNavigationBar': 'BottomNavigationBar',
    'BottomAppBar': 'BottomAppBar',
    'NavigationRail': 'NavigationRail',
    'Expansible': 'Expansible',
    'Menu': 'Menu',
    'MenuAnchor': 'Menu',
    'SuperMenuAnchor': 'Menu',
    'Tab': 'Tab',
    'Tabs': 'Tab',
    'AppBar': 'ApplicationBar',
    'BottomBar': 'BottomAppBar',
    'Rail': 'NavigationRail',
    'List': 'ListView',
  };

  /// Enregistre des alias supplémentaires de noms de composants (ex: extensions).
  static void registerAliases(Map<String, String> aliases) {
    _aliases.addAll(aliases);
  }

  /// Convertit un nom de type court (ex: `"Value"`, `"Card"`, `"AppBar"`) en
  /// identifiant de registre (`"registry:Value"`), tout en préservant les slots
  /// fournis par le code (`id == type` sans nom de composant connu).
  static String normalize(String type, {String? id}) {
    final trimmed = type.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Type de composant vide.');
    }
    if (trimmed.startsWith('registry:') ||
        trimmed.startsWith('factory:') ||
        trimmed.startsWith('component:') ||
        trimmed.startsWith('scaffold:') ||
        trimmed.startsWith('__')) {
      return trimmed;
    }
    final canonical = _aliases[trimmed];
    if (canonical != null) {
      return 'registry:$canonical';
    }
    return trimmed;
  }

  /// Retourne le nom court d'un type de registre standard (`"registry:Value"` -> `"Value"`),
  /// et conserve le préfixe pour les types personnalisés (`"registry:clock"`, `"factory:A"`).
  static String shortName(String type) {
    if (type.startsWith('registry:')) {
      final rest = type.substring('registry:'.length);
      if (_aliases.values.contains(rest)) {
        return rest;
      }
    }
    return type;
  }
}

/// Lecture et formatage souples des dimensions (`"64px"`, `"50%"`, `64`, ou Map).
abstract final class JsonDimension {
  static final _dimensionString = RegExp(
    r'^\s*([0-9]+(?:\.[0-9]+)?)\s*(px|%|percent)?\s*$',
    caseSensitive: false,
  );

  static SlotDimension parse(Object? value) {
    if (value is num) {
      if (!value.isFinite || value < 0) {
        throw const FormatException('Dimension de slot invalide.');
      }
      return SlotDimension(value.toDouble(), SlotSizeUnit.pixels);
    }
    if (value is String) {
      final match = _dimensionString.firstMatch(value);
      if (match == null) {
        throw const FormatException('Dimension de slot invalide.');
      }
      final number = double.tryParse(match.group(1)!);
      if (number == null || !number.isFinite || number < 0) {
        throw const FormatException('Dimension de slot invalide.');
      }
      final unitToken = (match.group(2) ?? 'px').toLowerCase();
      final unit = unitToken == '%' || unitToken == 'percent'
          ? SlotSizeUnit.percent
          : SlotSizeUnit.pixels;
      return SlotDimension(number, unit);
    }
    if (value is Map) {
      final rawValue = value['value'];
      final rawUnit = value['unit'];
      if (rawValue is! num ||
          !rawValue.isFinite ||
          rawValue < 0 ||
          (rawUnit != 'px' && rawUnit != 'percent' && rawUnit != '%')) {
        throw const FormatException('Dimension de slot invalide.');
      }
      return SlotDimension(
        rawValue.toDouble(),
        rawUnit == 'px' ? SlotSizeUnit.pixels : SlotSizeUnit.percent,
      );
    }
    throw const FormatException('Dimension de slot invalide.');
  }

  static String format(SlotDimension dimension) {
    final numText = dimension.value == dimension.value.roundToDouble()
        ? dimension.value.toInt().toString()
        : dimension.value.toString();
    return '$numText${dimension.unit == SlotSizeUnit.pixels ? 'px' : '%'}';
  }

  static Map<String, Object?> formatConstraintsCompact(
    SlotSizeConstraints constraints,
  ) => {
    if (constraints.percentBasis != SlotPercentBasis.zone)
      'percentBasis': constraints.percentBasis.name,
    if (constraints.padding != 0) 'padding': constraints.padding,
    if (constraints.paddingInsets != null)
      'paddingInsets': [
        constraints.paddingInsets!.top,
        constraints.paddingInsets!.right,
        constraints.paddingInsets!.bottom,
        constraints.paddingInsets!.left,
      ],
    for (final (key, dimension) in [
      ('minWidth', constraints.minWidth),
      ('minHeight', constraints.minHeight),
      ('maxWidth', constraints.maxWidth),
      ('maxHeight', constraints.maxHeight),
      ('preferredWidth', constraints.preferredWidth),
      ('preferredHeight', constraints.preferredHeight),
    ])
      if (dimension != null) key: format(dimension),
  };

  /// Lit une taille préférée depuis `{"width": w, "height": h}` ou `[w, h]`.
  static Size? parsePreferredSize(
    Object? value, {
    bool allowInfiniteSides = false,
  }) {
    if (value == null) return null;
    if (value is Map) {
      final width = value['width'];
      final height = value['height'];
      if (allowInfiniteSides && (width == null || height == null)) {
        final w = width == null
            ? double.infinity
            : (width is num && width.isFinite && width >= 0)
            ? width.toDouble()
            : throw const FormatException('Taille preferee invalide.');
        final h = height == null
            ? double.infinity
            : (height is num && height.isFinite && height >= 0)
            ? height.toDouble()
            : throw const FormatException('Taille preferee invalide.');
        return Size(w, h);
      }
      if (width is! num ||
          height is! num ||
          !width.isFinite ||
          !height.isFinite ||
          width <= 0 ||
          height <= 0) {
        throw const FormatException('Dimensions positives requises.');
      }
      return Size(width.toDouble(), height.toDouble());
    }
    if (value is List && value.length == 2) {
      final rawW = value[0];
      final rawH = value[1];
      if (allowInfiniteSides) {
        if ((rawW != null && (rawW is! num || !rawW.isFinite || rawW < 0)) ||
            (rawH != null && (rawH is! num || !rawH.isFinite || rawH < 0))) {
          throw const FormatException('Invalid native slot size.');
        }
        return Size(
          (rawW as num?)?.toDouble() ?? double.infinity,
          (rawH as num?)?.toDouble() ?? double.infinity,
        );
      }
      if (rawW is! num ||
          rawH is! num ||
          !rawW.isFinite ||
          !rawH.isFinite ||
          rawW <= 0 ||
          rawH <= 0) {
        throw const FormatException('Dimensions positives requises.');
      }
      return Size(rawW.toDouble(), rawH.toDouble());
    }
    throw const FormatException('Taille preferee invalide.');
  }

  /// Lit un `EdgeInsets` depuis un nombre uniforme, `[v, h]` ou `[t, r, b, l]`.
  static EdgeInsets parsePaddingInsets(Object? value, double maxPadding) {
    if (value is num && value.isFinite && value >= 0 && value <= maxPadding) {
      return EdgeInsets.all(value.toDouble());
    }
    if (value is List) {
      if (value.length == 2) {
        final v = value[0];
        final h = value[1];
        if (v is num &&
            h is num &&
            v.isFinite &&
            h.isFinite &&
            v >= 0 &&
            h >= 0 &&
            v <= maxPadding &&
            h <= maxPadding) {
          return EdgeInsets.symmetric(
            vertical: v.toDouble(),
            horizontal: h.toDouble(),
          );
        }
      } else if (value.length == 4) {
        final sides = <double>[];
        for (final side in value) {
          if (side is! num || !side.isFinite || side < 0 || side > maxPadding) {
            throw const FormatException('Marge de slot invalide.');
          }
          sides.add(side.toDouble());
        }
        return EdgeInsets.fromLTRB(sides[3], sides[0], sides[1], sides[2]);
      }
    }
    throw const FormatException('Marge de slot invalide.');
  }
}

/// Shared JSON parsing, encoding, and slot-layout equality/hash helpers.
abstract final class JsonReader {
  static T field<T>(
    Map<Object?, Object?> map,
    String key,
    T fallback, {
    required String context,
  }) {
    if (!map.containsKey(key)) return fallback;
    final result = map[key];
    if (result is! T) throw FormatException('Invalid $context "$key".');
    return result;
  }

  static double? nullableDouble(
    Map<Object?, Object?> map,
    String key,
    double? fallback, {
    required String context,
  }) {
    if (!map.containsKey(key)) return fallback;
    final result = map[key];
    if (result == null) return null;
    if (result is! num || !result.isFinite) {
      throw FormatException('Invalid $context "$key".');
    }
    return result.toDouble();
  }

  static Color? nullableColor(
    Map<Object?, Object?> map,
    String key,
    Color? fallback, {
    required String errorMessage,
  }) {
    if (!map.containsKey(key)) return fallback;
    try {
      return JsonColor.parseNullable(map[key], key);
    } on FormatException {
      throw FormatException(errorMessage);
    }
  }

  static T? enumByName<T extends Enum>(
    Iterable<T> values,
    Object? raw, [
    Map<String, T> aliases = const {},
  ]) {
    if (raw is! String) return null;
    final aliased = aliases[raw];
    if (aliased != null) return aliased;
    return values.where((candidate) => candidate.name == raw).firstOrNull;
  }

  static FontWeight? parseFontWeight(Object? weight) {
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

  static Map<E, JsonTextBinding> readPropertyBindings<E extends Enum>(
    Map<Object?, Object?> map,
    Iterable<E> values,
    Map<E, JsonTextBinding> fallback, {
    required String context,
  }) {
    final raw = map['propertyBindings'];
    if (raw != null && raw is! Map) {
      throw FormatException('Invalid $context property bindings.');
    }
    if (!map.containsKey('propertyBindings')) {
      return fallback;
    }
    final result = <E, JsonTextBinding>{};
    for (final entry in (raw as Map? ?? {}).entries) {
      if (entry.key is! String) {
        throw FormatException('Invalid $context property binding.');
      }
      final property = values
          .where((candidate) => candidate.name == entry.key)
          .firstOrNull;
      if (property == null || (entry.value is! Map && entry.value is! String)) {
        throw FormatException('Invalid $context property binding.');
      }
      result[property] = JsonTextBinding.fromJson(entry.value);
    }
    return result;
  }

  static Map<String, Object?> encodePropertyBindings<E extends Enum>(
    Map<E, JsonTextBinding> bindings, {
    bool compact = false,
  }) => {
    for (final entry in bindings.entries)
      entry.key.name: compact
          ? entry.value.toCompactJson()
          : entry.value.toJson(),
  };

  static bool sameSlotPlacements<K>(
    Map<K, List<String>> a,
    Map<K, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!listEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  static List<Object?> slotLayoutHashParts({
    required Map<Object?, List<String>> placements,
    required Map<Object?, Object?> slotTypes,
    required Map<Object?, Object?> zoneAxes,
    required Map<Object?, Object?> zoneFlows,
    Map<Object?, Object?>? zoneStyles,
    required Map<Object?, Object?> slotPreferredSizes,
    required Map<Object?, Object?> slotSizeConstraints,
    required Map<Object?, Object?> slotLabels,
  }) => [
    Object.hashAllUnordered(
      placements.entries.map(
        (e) => Object.hash(e.key, Object.hashAll(e.value)),
      ),
    ),
    Object.hashAllUnordered(
      slotTypes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      zoneAxes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      zoneFlows.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    if (zoneStyles != null)
      Object.hashAllUnordered(
        zoneStyles.entries.map((e) => Object.hash(e.key, e.value)),
      ),
    Object.hashAllUnordered(
      slotPreferredSizes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      slotSizeConstraints.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      slotLabels.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  ];

  /// Formate un nombre flottant sans `.0` superflu pour les résumés et info-bulles.
  static String formatNumber(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  /// Calcule le hash non ordonné d'une map `propertyBindings`.
  static int hashPropertyBindings<E>(Map<E, JsonTextBinding> bindings) =>
      Object.hashAllUnordered(
        bindings.entries.map((entry) => Object.hash(entry.key, entry.value)),
      );

  /// Collecte toutes les liaisons JSON référencées par un composant et ses états.
  static Iterable<JsonTextBinding> collectReferencedBindings<
    C extends ComponentConfig,
    P extends ComponentStateProperty<B>,
    B extends Enum,
    O extends ComponentConfigOverrideBase<C, P, B>
  >(
    Map<B, JsonTextBinding> propertyBindings,
    ComponentConfigStatesBase<C, P, B, O>? states,
    Map<B, JsonTextBinding> Function(C) bindingsOf, {
    JsonTextBinding? primaryBinding,
  }) => [
    ?primaryBinding,
    ?states?.binding,
    ...propertyBindings.values,
    for (final cfg in states?.named.values ?? <C>[]) ...bindingsOf(cfg).values,
    if (states?.hover case final h?) ...bindingsOf(h.config).values,
    if (states?.selected case final s?) ...bindingsOf(s.config).values,
    for (final auto in states?.automatic.values ?? <O>[])
      ...bindingsOf(auto.config).values,
  ];

  /// Lit une chaîne `'label'` avec repli sur l'alias `'text'`.
  static String readLabelOrText(
    Map<Object?, Object?> map,
    String fallback, {
    required String context,
  }) => map.containsKey('label')
      ? field(map, 'label', fallback, context: context)
      : map.containsKey('text')
      ? field(map, 'text', fallback, context: context)
      : fallback;

  /// Lit et valide une propriété `'fontFamily'` optionnelle.
  static String? readFontFamily(
    Map<Object?, Object?> map,
    String? fallback, {
    required String errorMessage,
  }) {
    final raw = map.containsKey('fontFamily') ? map['fontFamily'] : fallback;
    if (raw != null && raw is! String) {
      throw FormatException(errorMessage);
    }
    return raw as String?;
  }

  /// Lit et valide une propriété `'fontWeight'` optionnelle.
  static FontWeight? readFontWeight(
    Map<Object?, Object?> map,
    FontWeight? fallback, {
    required String errorMessage,
  }) {
    if (!map.containsKey('fontWeight')) return fallback;
    final raw = map['fontWeight'];
    if (raw == null) return null;
    return parseFontWeight(raw) ?? (throw FormatException(errorMessage));
  }

  /// Lit et fusionne une propriété `'style'` ([ContainerStyle]) dans une Map JSON.
  static ContainerStyle readPatchedStyle(
    Map<Object?, Object?> map,
    ContainerStyle fallback, {
    required String context,
    String key = 'style',
  }) {
    if (!map.containsKey(key) || map[key] == null) {
      return map.containsKey(key) ? const ContainerStyle() : fallback;
    }
    if (map[key] is Map) {
      return fallback.patchFromJson(map[key] as Map);
    }
    throw FormatException('Invalid $context "$key".');
  }

  /// Vérifie la validité des attributs typographiques et de boîte d'un composant feuille.
  static bool hasInvalidTypographyOrBox({
    String? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? iconSize,
    double? iconSpacing,
    double? radius,
    double? borderWidth,
    double? elevation,
    double? horizontalPadding,
    double? verticalPadding,
  }) =>
      (fontFamily != null && fontFamily.trim().isEmpty) ||
      (fontSize != null && (!fontSize.isFinite || fontSize <= 0)) ||
      (lineHeight != null && (!lineHeight.isFinite || lineHeight <= 0)) ||
      (letterSpacing != null && !letterSpacing.isFinite) ||
      (iconSize != null && (!iconSize.isFinite || iconSize <= 0)) ||
      (iconSpacing != null && (!iconSpacing.isFinite || iconSpacing < 0)) ||
      (radius != null && (!radius.isFinite || radius < 0)) ||
      (borderWidth != null && (!borderWidth.isFinite || borderWidth < 0)) ||
      (elevation != null && (!elevation.isFinite || elevation < 0)) ||
      (horizontalPadding != null &&
          (!horizontalPadding.isFinite || horizontalPadding < 0)) ||
      (verticalPadding != null &&
          (!verticalPadding.isFinite || verticalPadding < 0));

  /// Normalise une map de placements par zone en listes immuables.
  static Map<String, List<String>> normalizePlacements(
    Map<String, List<String>> placements, {
    bool dropEmptyZones = true,
  }) => Map.unmodifiable({
    for (final entry in placements.entries)
      if (!dropEmptyZones || entry.value.isNotEmpty)
        entry.key: List<String>.unmodifiable(entry.value),
  });

  /// Normalise une map de [ZoneFlowConfig] en omettant les valeurs par défaut.
  static Map<String, ZoneFlowConfig> normalizeZoneFlows(
    Map<String, ZoneFlowConfig> flows,
  ) => Map.unmodifiable({
    for (final entry in flows.entries)
      if (!entry.value.isDefault) entry.key: entry.value,
  });

  /// Normalise une map de libellés de slots en supprimant les entrées vides.
  static Map<String, String> normalizeSlotLabels(
    Map<String, String> slotLabels,
  ) => Map.unmodifiable({
    for (final entry in slotLabels.entries)
      if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
  });

  /// Vérifie la cohérence et l'unicité des identifiants de zones et de slots.
  static bool hasInvalidSlotContainerMaps({
    required Map<String, List<String>> placements,
    required Map<String, String> slotTypes,
    required Map<String, Axis> zoneAxes,
    required Map<String, ZoneFlowConfig> zoneFlows,
    required Map<String, Size?> slotPreferredSizes,
    required Map<String, SlotSizeConstraints> slotSizeConstraints,
    required Map<String, String> slotLabels,
    Iterable<String> extraZoneKeys = const [],
  }) {
    final ids = placements.values.expand((value) => value).toList();
    return ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length ||
        placements.keys.any((id) => id.trim().isEmpty) ||
        zoneAxes.keys.any((id) => id.trim().isEmpty) ||
        zoneFlows.keys.any((id) => id.trim().isEmpty) ||
        extraZoneKeys.any((id) => id.trim().isEmpty) ||
        slotTypes.keys.any((id) => id.trim().isEmpty) ||
        slotTypes.values.any((type) => type.trim().isEmpty) ||
        slotPreferredSizes.keys.any((id) => id.trim().isEmpty) ||
        slotSizeConstraints.keys.any((id) => id.trim().isEmpty) ||
        slotLabels.keys.any((id) => id.trim().isEmpty) ||
        slotPreferredSizes.values.any(
          (size) =>
              size != null &&
              (size.width.isNaN ||
                  size.height.isNaN ||
                  size.width < 0 ||
                  size.height < 0),
        );
  }

  /// Compare les métadonnées de placement et de zones entre deux conteneurs de slots.
  static bool sameSlotLayoutMetadata({
    required Map<String, List<String>> placementsA,
    required Map<String, List<String>> placementsB,
    required Map<String, String> slotTypesA,
    required Map<String, String> slotTypesB,
    required Map<String, Axis> zoneAxesA,
    required Map<String, Axis> zoneAxesB,
    required Map<String, ZoneFlowConfig> zoneFlowsA,
    required Map<String, ZoneFlowConfig> zoneFlowsB,
    required Map<String, Size?> slotPreferredSizesA,
    required Map<String, Size?> slotPreferredSizesB,
    required Map<String, SlotSizeConstraints> slotSizeConstraintsA,
    required Map<String, SlotSizeConstraints> slotSizeConstraintsB,
    required Map<String, String> slotLabelsA,
    required Map<String, String> slotLabelsB,
  }) =>
      sameSlotPlacements(placementsA, placementsB) &&
      mapEquals(slotTypesA, slotTypesB) &&
      mapEquals(zoneAxesA, zoneAxesB) &&
      mapEquals(zoneFlowsA, zoneFlowsB) &&
      mapEquals(slotPreferredSizesA, slotPreferredSizesB) &&
      mapEquals(slotSizeConstraintsA, slotSizeConstraintsB) &&
      mapEquals(slotLabelsA, slotLabelsB);

  /// Ajoute un slot [id] dans [zone] et retourne les maps de métadonnées mises à jour.
  static ({
    Map<String, List<String>> placements,
    Map<String, String> slotTypes,
    Map<String, Size?> slotPreferredSizes,
    Map<String, SlotSizeConstraints> slotSizeConstraints,
    Map<String, String> slotLabels,
  })
  addSlotToMaps({
    required String id,
    required String zone,
    String? type,
    bool replace = false,
    required Map<String, List<String>> placements,
    required Map<String, String> slotTypes,
    required Map<String, Size?> slotPreferredSizes,
    required Map<String, SlotSizeConstraints> slotSizeConstraints,
    required Map<String, String> slotLabels,
  }) {
    final next = <String, List<String>>{
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    };
    final replaced = replace ? next.remove(zone) ?? <String>[] : <String>[];
    next.putIfAbsent(zone, () => []).add(id);
    final types = {...slotTypes}
      ..removeWhere((key, _) => key == id || replaced.contains(key));
    if (type != null && type != id) types[id] = type;
    return (
      placements: next,
      slotTypes: types,
      slotPreferredSizes: {...slotPreferredSizes}
        ..removeWhere((key, _) => replaced.contains(key)),
      slotSizeConstraints: {...slotSizeConstraints}
        ..removeWhere((key, _) => replaced.contains(key)),
      slotLabels: {...slotLabels}
        ..removeWhere((key, _) => replaced.contains(key)),
    );
  }

  /// Supprime un ensemble de slots [removedIds] (et une zone optionnelle [removedZone]) des maps.
  static ({
    Map<String, List<String>> placements,
    Map<String, String> slotTypes,
    Map<String, Size?> slotPreferredSizes,
    Map<String, SlotSizeConstraints> slotSizeConstraints,
    Map<String, String> slotLabels,
  })
  removeSlotsFromMaps({
    required Set<String> removedIds,
    String? removedZone,
    required Map<String, List<String>> placements,
    required Map<String, String> slotTypes,
    required Map<String, Size?> slotPreferredSizes,
    required Map<String, SlotSizeConstraints> slotSizeConstraints,
    required Map<String, String> slotLabels,
  }) => (
    placements: {
      for (final entry in placements.entries)
        if (entry.key != removedZone)
          entry.key: entry.value
              .where((value) => !removedIds.contains(value))
              .toList(),
    },
    slotTypes: {...slotTypes}..removeWhere((k, _) => removedIds.contains(k)),
    slotPreferredSizes: {...slotPreferredSizes}
      ..removeWhere((k, _) => removedIds.contains(k)),
    slotSizeConstraints: {...slotSizeConstraints}
      ..removeWhere((k, _) => removedIds.contains(k)),
    slotLabels: {...slotLabels}..removeWhere((k, _) => removedIds.contains(k)),
  );

  /// Déplace un slot [id] vers [zone] avant [beforeId] ou après [afterId].
  static Map<String, List<String>>? moveSlotInPlacements({
    required String id,
    required String zone,
    String? beforeId,
    String? afterId,
    required Map<String, List<String>> placements,
    required String unknownError,
    required String destinationError,
  }) {
    if (!placements.values.any((ids) => ids.contains(id))) {
      throw ArgumentError.value(id, 'id', unknownError);
    }
    final zoneSlots = placements[zone] ?? const <String>[];
    if (zone.trim().isEmpty ||
        (beforeId != null && afterId != null) ||
        (beforeId != null && !zoneSlots.contains(beforeId)) ||
        (afterId != null && !zoneSlots.contains(afterId))) {
      throw ArgumentError(destinationError);
    }
    if (beforeId == id || afterId == id) return null;
    final next = <String, List<String>>{
      for (final entry in placements.entries)
        entry.key: entry.value.where((value) => value != id).toList(),
    };
    final destination = next.putIfAbsent(zone, () => []);
    final index = beforeId != null
        ? destination.indexOf(beforeId)
        : afterId != null
        ? destination.indexOf(afterId) + 1
        : destination.length;
    destination.insert(index, id);
    return next;
  }

  /// Remplace un slot [id] par [replacementId] de type [type] en conservant ses contraintes.
  static ({
    Map<String, List<String>> placements,
    Map<String, String> slotTypes,
    Map<String, Axis> zoneAxes,
    Map<String, ZoneFlowConfig> zoneFlows,
    Map<String, Size?> slotPreferredSizes,
    Map<String, SlotSizeConstraints> slotSizeConstraints,
    Map<String, String> slotLabels,
  })
  replaceSlotInMaps({
    required String id,
    required String replacementId,
    required String type,
    required Map<String, List<String>> placements,
    required Map<String, String> slotTypes,
    Map<String, Axis> zoneAxes = const {},
    Map<String, ZoneFlowConfig> zoneFlows = const {},
    required Map<String, Size?> slotPreferredSizes,
    required Map<String, SlotSizeConstraints> slotSizeConstraints,
    required Map<String, String> slotLabels,
    String Function(String zone)? remapZone,
    String errorMessage = 'Invalid slot replacement.',
  }) {
    if (!placements.values.any((ids) => ids.contains(id)) ||
        replacementId.trim().isEmpty ||
        placements.values.any((ids) => ids.contains(replacementId))) {
      throw ArgumentError(errorMessage);
    }
    final zoneMapper = remapZone ?? ((String z) => z);
    return (
      placements: {
        for (final entry in placements.entries)
          zoneMapper(entry.key): [
            for (final slot in entry.value) slot == id ? replacementId : slot,
          ],
      },
      slotTypes: {...slotTypes}
        ..remove(id)
        ..[replacementId] = type,
      zoneAxes: {
        for (final entry in zoneAxes.entries)
          zoneMapper(entry.key): entry.value,
      },
      zoneFlows: {
        for (final entry in zoneFlows.entries)
          zoneMapper(entry.key): entry.value,
      },
      slotPreferredSizes: {
        for (final entry in slotPreferredSizes.entries)
          (entry.key == id ? replacementId : entry.key): entry.value,
      },
      slotSizeConstraints: {
        for (final entry in slotSizeConstraints.entries)
          (entry.key == id ? replacementId : entry.key): entry.value,
      },
      slotLabels: {...slotLabels}..remove(id),
    );
  }

  /// Met à jour ou retire l'axe d'une zone dans [zoneAxes].
  static Map<String, Axis> updateZoneAxisMap(
    Map<String, Axis> zoneAxes,
    String zone,
    Axis? axis, {
    Axis? defaultAxis,
  }) {
    final next = {...zoneAxes};
    if (axis == null || axis == defaultAxis) {
      next.remove(zone);
    } else {
      next[zone] = axis;
    }
    return next;
  }

  /// Met à jour ou retire la configuration de flux d'une zone dans [zoneFlows].
  static Map<String, ZoneFlowConfig> updateZoneFlowMap(
    Map<String, ZoneFlowConfig> zoneFlows,
    String zone,
    ZoneFlowConfig flow,
  ) {
    final next = {...zoneFlows};
    if (flow.isDefault) {
      next.remove(zone);
    } else {
      next[zone] = flow;
    }
    return next;
  }

  /// Encode en JSON les maps de slots et de zones d'un conteneur.
  static Map<String, Object?> encodeSlotContainerJson({
    required Map<String, List<String>> placements,
    required String Function(String id) slotTypeOf,
    required Map<String, Axis> zoneAxes,
    required Map<String, ZoneFlowConfig> zoneFlows,
    Map<String, ContainerStyle> zoneStyles = const {},
    required Map<String, Size?> slotPreferredSizes,
    required Map<String, SlotSizeConstraints> slotSizeConstraints,
    required Map<String, String> slotLabels,
    bool compact = false,
    bool alwaysIncludePlacements = false,
    bool useShortTypeNameInFullJson = true,
    bool allowBareSlotIdInFullJson = true,
    String axesKey = 'zoneAxes',
    String flowsKey = 'zoneFlows',
  }) {
    final useCompactConstraints = compact;
    final useShortNames = compact || useShortTypeNameInFullJson;
    final allowBareId = !compact && allowBareSlotIdInFullJson;
    return {
      if (alwaysIncludePlacements || placements.isNotEmpty)
        'placements': {
          for (final entry in placements.entries)
            if (!alwaysIncludePlacements ? entry.value.isNotEmpty : true)
              entry.key: [
                for (final id in entry.value)
                  if (allowBareId && slotTypeOf(id) == id)
                    id
                  else
                    {
                      'id': id,
                      'type': useShortNames
                          ? JsonComponentType.shortName(slotTypeOf(id))
                          : slotTypeOf(id),
                    },
              ],
        },
      if (zoneAxes.isNotEmpty)
        axesKey: {
          for (final entry in zoneAxes.entries) entry.key: entry.value.name,
        },
      if (zoneFlows.isNotEmpty)
        flowsKey: {
          for (final entry in zoneFlows.entries)
            if (!entry.value.isDefault) entry.key: entry.value.toJson(),
        },
      if (zoneStyles.isNotEmpty)
        'zoneStyles': {
          for (final entry in zoneStyles.entries)
            if (entry.value != const ContainerStyle())
              entry.key: compact
                  ? entry.value.toCompactJson()
                  : entry.value.toJson(),
        },
      if (slotPreferredSizes.isNotEmpty)
        'slotPreferredSizes': {
          for (final entry in slotPreferredSizes.entries)
            entry.key: entry.value == null
                ? null
                : [
                    entry.value!.width.isFinite ? entry.value!.width : null,
                    entry.value!.height.isFinite ? entry.value!.height : null,
                  ],
        },
      if (slotSizeConstraints.isNotEmpty)
        'slotSizeConstraints': {
          for (final entry in slotSizeConstraints.entries)
            entry.key: useCompactConstraints
                ? JsonDimension.formatConstraintsCompact(entry.value)
                : entry.value.toJson(),
        },
      if (slotLabels.isNotEmpty) 'slotLabels': slotLabels,
    };
  }

  /// Décode les placements (`placements` et `slotTypes`) d'un conteneur de slots.
  static ({Map<String, List<String>> placements, Map<String, String> slotTypes})
  parseSlotPlacements(
    Object? rawPlacements, {
    required String invalidPlacementsMessage,
    required String invalidZoneMessage,
    required String invalidSlotMessage,
  }) {
    final map = rawPlacements ?? const {};
    if (map is! Map) {
      throw FormatException(invalidPlacementsMessage);
    }
    final placements = <String, List<String>>{};
    final types = <String, String>{};
    for (final entry in map.entries) {
      if (entry.key is! String || entry.value is! List) {
        throw FormatException(invalidZoneMessage);
      }
      final ids = <String>[];
      for (final slot in entry.value as List) {
        if (slot is String && slot.trim().isNotEmpty) {
          ids.add(slot);
          types[slot] = JsonComponentType.normalize(slot, id: slot);
          continue;
        }
        if (slot is! Map || slot['id'] is! String || slot['type'] is! String) {
          throw FormatException(invalidSlotMessage);
        }
        final id = slot['id'] as String;
        ids.add(id);
        types[id] = JsonComponentType.normalize(slot['type'] as String, id: id);
      }
      placements[entry.key as String] = ids;
    }
    return (placements: placements, slotTypes: types);
  }

  /// Décode les maps de métadonnées de zones et de slots d'un conteneur.
  static ({
    Map<String, Axis> zoneAxes,
    Map<String, ZoneFlowConfig> zoneFlows,
    Map<String, ContainerStyle> zoneStyles,
    Map<String, Size?> slotPreferredSizes,
    Map<String, SlotSizeConstraints> slotSizeConstraints,
    Map<String, String> slotLabels,
  })
  parseSlotContainerMetadata(
    Map<Object?, Object?> value, {
    required Iterable<String> placedIds,
    String axesKey = 'zoneAxes',
    String flowsKey = 'zoneFlows',
    bool parseZoneStyles = false,
    required String invalidMetadataMessage,
    required String invalidLabelsMessage,
    required String invalidAxisMessage,
    required String invalidFlowMessage,
    String invalidStyleMessage = 'Style de zone invalide.',
    required String invalidConstraintMessage,
    required String invalidSizeMessage,
  }) {
    final rawSizes = value['slotPreferredSizes'] ?? const {};
    final rawConstraints = value['slotSizeConstraints'] ?? const {};
    final rawLabels = value['slotLabels'] ?? const {};
    final rawAxes = value[axesKey] ?? const {};
    final rawFlows = value[flowsKey] ?? const {};
    final rawStyles = parseZoneStyles
        ? (value['zoneStyles'] ?? const {})
        : const {};
    if (rawSizes is! Map ||
        rawConstraints is! Map ||
        rawLabels is! Map ||
        rawAxes is! Map ||
        rawFlows is! Map ||
        rawStyles is! Map) {
      throw FormatException(invalidMetadataMessage);
    }
    if (rawLabels.entries.any(
      (entry) => entry.key is! String || entry.value is! String,
    )) {
      throw FormatException(invalidLabelsMessage);
    }
    final parsedAxes = <String, Axis>{};
    for (final entry in rawAxes.entries) {
      if (entry.key is! String) {
        throw FormatException(invalidAxisMessage);
      }
      final axis = Axis.values
          .where((candidate) => candidate.name == entry.value)
          .firstOrNull;
      if (axis == null) {
        throw FormatException(invalidAxisMessage);
      }
      parsedAxes[entry.key as String] = axis;
    }
    final parsedFlows = <String, ZoneFlowConfig>{};
    for (final entry in rawFlows.entries) {
      if (entry.key is! String) {
        throw FormatException(invalidFlowMessage);
      }
      parsedFlows[entry.key as String] = ZoneFlowConfig.fromJson(entry.value);
    }
    final parsedStyles = <String, ContainerStyle>{};
    if (parseZoneStyles) {
      for (final entry in rawStyles.entries) {
        if (entry.key is! String) {
          throw FormatException(invalidStyleMessage);
        }
        parsedStyles[entry.key as String] = ContainerStyle.fromJson(
          entry.value,
        );
      }
    }
    if (rawConstraints.keys.any((key) => key is! String)) {
      throw FormatException(invalidConstraintMessage);
    }
    final sizes = <String, Size?>{};
    for (final entry in rawSizes.entries) {
      if (entry.key is! String) {
        throw FormatException(invalidSizeMessage);
      }
      sizes[entry.key as String] = JsonDimension.parsePreferredSize(
        entry.value,
        allowInfiniteSides: true,
      );
    }
    return (
      zoneAxes: parsedAxes,
      zoneFlows: parsedFlows,
      zoneStyles: parsedStyles,
      slotPreferredSizes: sizes,
      slotSizeConstraints: SlotSizeConstraints.parseMap(
        rawConstraints,
        placedIds: placedIds,
      ),
      slotLabels: Map<String, String>.from(rawLabels),
    );
  }
}
