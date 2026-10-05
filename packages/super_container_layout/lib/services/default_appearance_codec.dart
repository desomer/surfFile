import '../theme/appearance.dart';
import '../theme/default_appearance.dart';
import 'appearance_store.dart';

/// Opt-in persistence for the reusable dimensions and scrolling preferences.
class DefaultAppearanceCodec extends AppearanceCodec {
  const DefaultAppearanceCodec();

  @override
  String get format => 'super_container_layout.default_appearance';

  @override
  Set<String> get additionalKeys => const {
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
  DefaultAppearance get defaults => DefaultAppearance();

  @override
  Map<String, Object?> toJson(Appearance appearance) {
    if (appearance is! DefaultAppearance) {
      throw ArgumentError.value(
        appearance,
        'appearance',
        'DefaultAppearanceCodec requires DefaultAppearance.',
      );
    }
    return {
      ...super.toJson(appearance),
      'cardHeight': appearance.cardHeight,
      'cardWidth': appearance.cardWidth,
      'rowHeight': appearance.rowHeight,
      'spacing': appearance.spacing,
      'fontSize': appearance.fontSize,
      'iconSize': appearance.iconSize,
      'scrollFadeEnabled': appearance.scrollFadeEnabled,
      'scrollFadeExtent': appearance.scrollFadeExtent,
    };
  }

  @override
  DefaultAppearance fromJson(Map<String, dynamic> json) {
    final base = super.fromJson(json);
    double number(String key, double fallback, {bool allowZero = false}) {
      final value = json[key] ?? fallback;
      if (value is! num ||
          !value.isFinite ||
          (allowZero ? value < 0 : value <= 0)) {
        throw FormatException('Invalid "$key".');
      }
      return value.toDouble();
    }

    final fade = json['scrollFadeEnabled'] ?? true;
    if (fade is! bool) {
      throw const FormatException('Invalid "scrollFadeEnabled".');
    }
    final initial = defaults;
    return DefaultAppearance(
      mode: base.mode,
      accent: base.accent,
      backgroundOpacity: base.backgroundOpacity,
      windowOpacity: base.windowOpacity,
      windowEffect: base.windowEffect,
      styles: base.styles,
      layouts: base.layouts,
      cardHeight: number('cardHeight', initial.cardHeight),
      cardWidth: number('cardWidth', initial.cardWidth),
      rowHeight: number('rowHeight', initial.rowHeight),
      spacing: number('spacing', initial.spacing, allowZero: true),
      fontSize: number('fontSize', initial.fontSize),
      iconSize: number('iconSize', initial.iconSize),
      scrollFadeEnabled: fade,
      scrollFadeExtent: number(
        'scrollFadeExtent',
        initial.scrollFadeExtent,
        allowZero: true,
      ),
    );
  }
}
