/// Action de comportement réactive liant la taille d'une zone de `SuperLayout` ([ZoneSizeBindingAction]).
///
/// Observe une valeur numérique issue d'un repository JSON via [JsonTextBinding]
/// et anime l'épaisseur de la zone cible selon une courbe [BehaviorCurve].
library;

import 'package:material_ui/material_ui.dart';

import '../component_behavior.dart';
import '../json_text_binding.dart';
import '../super_layout_config.dart';

/// Courbes d'animation sérialisables proposées par les comportements.
enum BehaviorCurve {
  linear('Linéaire', Curves.linear),
  easeIn('Accélération', Curves.easeIn),
  easeOut('Décélération', Curves.easeOut),
  easeInOut('Douce', Curves.easeInOut),
  fastOutSlowIn('Material', Curves.fastOutSlowIn),
  easeOutBack('Rebond léger', Curves.easeOutBack);

  const BehaviorCurve(this.label, this.curve);

  final String label;
  final Curve curve;
}

/// Lie la taille d'un côté d'un `SuperLayout` (ouest, est, nord ou sud) à une
/// valeur numérique d'un repository JSON, avec une animation entre l'ancienne
/// et la nouvelle taille.
///
/// La valeur est une épaisseur en pixels, ou un pourcentage de la largeur
/// (ouest / est) ou de la hauteur (nord / sud) du layout. `0` (ou une valeur
/// négative) ferme la zone ; une valeur absente ou non numérique rend la
/// taille configurée. La taille appliquée n'est jamais enregistrée dans la
/// configuration du layout.
@immutable
class ZoneSizeBindingAction extends BehaviorAction {
  ZoneSizeBindingAction({
    required this.zone,
    required this.binding,
    this.unit = SlotSizeUnit.pixels,
    this.durationMs = defaultDurationMs,
    this.curve = BehaviorCurve.easeInOut,
  }) {
    if (!zone.isSide) {
      throw ArgumentError.value(zone, 'zone', 'Un côté est requis.');
    }
    if (durationMs < 0) {
      throw ArgumentError.value(durationMs, 'durationMs', 'Durée négative.');
    }
    binding.validate();
  }

  static const defaultDurationMs = 250;

  final SuperLayoutZone zone;
  final JsonTextBinding binding;
  final SlotSizeUnit unit;
  final int durationMs;
  final BehaviorCurve curve;

  Duration get duration => Duration(milliseconds: durationMs);

  @override
  String get type => 'bindZoneSize';
  @override
  String get label => 'Taille de zone liée';
  @override
  String get description =>
      '${zone.label} ← ${binding.path} '
      '(${unit == SlotSizeUnit.percent ? '%' : 'px'}, $durationMs ms)';
  @override
  IconData get icon => Icons.width_normal_outlined;

  /// Sans effet : le `SuperLayout` observe lui-même la valeur liée.
  @override
  Future<void> execute(BuildContext context) async {}

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'zone': zone.name,
    'binding': binding.toJson(),
    'unit': unit.name,
    'durationMs': durationMs,
    'curve': curve.name,
  };

  factory ZoneSizeBindingAction.fromJson(Map<String, dynamic> json) {
    T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((value) => value.name == name).firstOrNull ?? fallback;
    final zone = SuperLayoutZone.values
        .where((zone) => zone.name == json['zone'])
        .firstOrNull;
    if (zone == null) {
      throw FormatException('Zone invalide : ${json['zone']}');
    }
    return ZoneSizeBindingAction(
      zone: zone,
      binding: JsonTextBinding.fromJson(json['binding']),
      unit: byName(SlotSizeUnit.values, json['unit'], SlotSizeUnit.pixels),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? defaultDurationMs,
      curve: byName(
        BehaviorCurve.values,
        json['curve'],
        BehaviorCurve.easeInOut,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZoneSizeBindingAction &&
          other.zone == zone &&
          other.binding == binding &&
          other.unit == unit &&
          other.durationMs == durationMs &&
          other.curve == curve;

  @override
  int get hashCode => Object.hash(zone, binding, unit, durationMs, curve);
}
