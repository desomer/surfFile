import 'dart:ui' show Color, FontWeight, Size;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart' show EdgeInsets;

import 'json_text_binding.dart';
import 'super_layout_config.dart'
    show SlotDimension, SlotPercentBasis, SlotSizeConstraints, SlotSizeUnit;

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
  static const Map<String, String> _aliases = {
    'Value': 'Value',
    'Action': 'Action',
    'Button': 'Action',
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
    'Chart': 'Chart',
    'Graph': 'Chart',
    'SuperChart': 'Chart',
    'AppBar': 'ApplicationBar',
    'BottomBar': 'BottomAppBar',
    'Rail': 'NavigationRail',
    'List': 'ListView',
  };

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
      if (property == null ||
          (entry.value is! Map && entry.value is! String)) {
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
      placements.entries.map((e) => Object.hash(e.key, Object.hashAll(e.value))),
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
}

