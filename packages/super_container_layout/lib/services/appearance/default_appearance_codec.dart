import '../../theme/appearance.dart';
import '../../theme/default_appearance.dart';
import 'appearance_codec.dart';

/// Opt-in persistence for the reusable dimensions and scrolling preferences.
class DefaultAppearanceCodec extends AppearanceCodec {
  const DefaultAppearanceCodec();

  static const dimensionKeys = {
    'cardHeight',
    'cardWidth',
    'rowHeight',
    'spacing',
    'fontSize',
    'iconSize',
    'scrollFadeEnabled',
    'scrollFadeExtent',
  };

  @override
  String get format => 'super_container_layout.default_appearance';

  @override
  Set<String> get additionalKeys => dimensionKeys;

  @override
  DefaultAppearance get defaults => DefaultAppearance();

  static Map<String, Object?> encodeDimensions(DefaultAppearance a) => {
    'cardHeight': a.cardHeight,
    'cardWidth': a.cardWidth,
    'rowHeight': a.rowHeight,
    'spacing': a.spacing,
    'fontSize': a.fontSize,
    'iconSize': a.iconSize,
    'scrollFadeEnabled': a.scrollFadeEnabled,
    'scrollFadeExtent': a.scrollFadeExtent,
  };

  static double readBoundedDouble(
    Map<String, dynamic> map,
    String key,
    double fallback,
    double min,
    double max,
  ) {
    final value = map[key] ?? fallback;
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException('Valeur invalide pour "$key".');
    }
    return value.toDouble();
  }

  static DefaultAppearance decodeDimensions(
    Map<String, dynamic> map, {
    required Appearance base,
    DefaultAppearance? defaults,
    bool enforceBounds = false,
  }) {
    final initial = defaults ?? DefaultAppearance();
    double number(
      String key,
      double fallback, {
      required double min,
      required double max,
      bool allowZero = false,
    }) {
      if (enforceBounds) {
        return readBoundedDouble(map, key, fallback, min, max);
      }
      final value = map[key] ?? fallback;
      if (value is! num ||
          !value.isFinite ||
          (allowZero ? value < 0 : value <= 0)) {
        throw FormatException('Invalid "$key".');
      }
      return value.toDouble();
    }

    final fade = map['scrollFadeEnabled'] ?? initial.scrollFadeEnabled;
    if (fade is! bool) {
      throw const FormatException('Invalid "scrollFadeEnabled".');
    }
    return DefaultAppearance(
      mode: base.mode,
      accent: base.accent,
      backgroundOpacity: base.backgroundOpacity,
      windowOpacity: base.windowOpacity,
      windowEffect: base.windowEffect,
      styles: base.styles,
      layouts: base.layouts,
      components: base.components,
      behaviors: base.behaviors,
      pageCatalog: base.pageCatalog,
      cardHeight: number(
        'cardHeight',
        initial.cardHeight,
        min: DefaultAppearance.minCardHeight,
        max: DefaultAppearance.maxCardHeight,
      ),
      cardWidth: number(
        'cardWidth',
        initial.cardWidth,
        min: DefaultAppearance.minCardWidth,
        max: DefaultAppearance.maxCardWidth,
      ),
      rowHeight: number(
        'rowHeight',
        initial.rowHeight,
        min: DefaultAppearance.minRowHeight,
        max: DefaultAppearance.maxRowHeight,
      ),
      spacing: number(
        'spacing',
        initial.spacing,
        min: DefaultAppearance.minSpacing,
        max: DefaultAppearance.maxSpacing,
        allowZero: true,
      ),
      fontSize: number(
        'fontSize',
        initial.fontSize,
        min: DefaultAppearance.minFontSize,
        max: DefaultAppearance.maxFontSize,
      ),
      iconSize: number(
        'iconSize',
        initial.iconSize,
        min: DefaultAppearance.minIconSize,
        max: DefaultAppearance.maxIconSize,
      ),
      scrollFadeEnabled: fade,
      scrollFadeExtent: number(
        'scrollFadeExtent',
        initial.scrollFadeExtent,
        min: DefaultAppearance.minScrollFadeExtent,
        max: DefaultAppearance.maxScrollFadeExtent,
        allowZero: true,
      ),
    );
  }

  @override
  Map<String, Object?> toJson(Appearance a) {
    if (a is! DefaultAppearance) {
      throw ArgumentError.value(
        a,
        'appearance',
        'DefaultAppearanceCodec requires DefaultAppearance.',
      );
    }
    return {
      ...super.toJson(a),
      ...encodeDimensions(a),
    };
  }

  @override
  DefaultAppearance fromJson(Map<String, dynamic> json) =>
      decodeDimensions(json, base: super.fromJson(json), defaults: defaults);
}
