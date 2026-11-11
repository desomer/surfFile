/// Modélisation des comportements interactifs ([ComponentBehavior]) attachés aux composants.
///
/// Associe un déclencheur ([BehaviorTrigger], ex. clic) à une action polymorphe
/// ([BehaviorAction], telle que la navigation [GoToPageAction]), stockée dans
/// `Appearance.behaviors`.
///
/// Les actions concrètes vivent dans `models/behaviours/` et sont réexportées ici :
/// - [EmitEventAction] (`behaviours/emit_event_action.dart`)
/// - [GoToPageAction] (`behaviours/go_to_page_action.dart`)
/// - [StateBindingAction] (`behaviours/state_binding_action.dart`)
/// - [TooltipAction] (`behaviours/tooltip_action.dart`)
/// - [ZoneSizeBindingAction] (`behaviours/zone_size_binding_action.dart`)
library;

import 'package:material_ui/material_ui.dart';

import '../services/events/super_event_bus.dart';
import 'behaviours/emit_event_action.dart';
import 'behaviours/go_to_page_action.dart';
import 'behaviours/state_binding_action.dart';
import 'behaviours/tooltip_action.dart';
import 'behaviours/zone_size_binding_action.dart';

export 'behaviours/emit_event_action.dart';
export 'behaviours/go_to_page_action.dart';
export 'behaviours/state_binding_action.dart';
export 'behaviours/tooltip_action.dart';
export 'behaviours/zone_size_binding_action.dart';

/// Déclencheur d'un comportement sur un composant.
enum BehaviorTrigger {
  click('Clic', 'Sur un clic', Icons.touch_app_outlined),
  doubleClick('Double-clic', 'Sur un double-clic', Icons.touch_app_outlined),

  /// Affichage déclaratif d'une info-bulle au survol.
  hover('Survol', 'Au survol du composant', Icons.info_outline),

  /// Comportement réactif : appliqué quand la valeur liée change.
  binding('Liaison', 'Quand la valeur liée change', Icons.link);

  /// Déclencheurs provoqués par un geste de l'utilisateur.
  static const gestures = [click, doubleClick];

  const BehaviorTrigger(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// Action exécutée par un [ComponentBehavior].
@immutable
abstract class BehaviorAction {
  const BehaviorAction();

  String get type;
  String get label;
  String get description;
  IconData get icon;

  Map<String, Object?> toJson();
  Future<void> execute(BuildContext context);

  /// Execute avec les donnees de l'instance, sans modifier les actions existantes.
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) => execute(context);
}

/// Metadonnees runtime de l'instance ayant declenche un comportement.
@immutable
class BehaviorExecutionData {
  BehaviorExecutionData({
    required this.componentId,
    required this.componentType,
    required this.trigger,
    Map<String, Object?> data = const {},
  }) : data = immutableEventJson(data);

  final String componentId;
  final String componentType;
  final BehaviorTrigger trigger;
  final Map<String, Object?> data;
}

/// Registre extensible pour décoder les actions polymorphes.
abstract final class BehaviorActionCatalog {
  static final Map<String, BehaviorAction Function(Map<String, dynamic> json)>
  _codecs = {
    'goToPage': GoToPageAction.fromJson,
    'emitEvent': EmitEventAction.fromJson,
    'bindZoneSize': ZoneSizeBindingAction.fromJson,
    'bindState': StateBindingAction.fromJson,
    'onTooltip': TooltipAction.fromJson,
  };

  static void register(
    String type,
    BehaviorAction Function(Map<String, dynamic> json) fromJson,
  ) {
    _codecs[type.trim()] = fromJson;
  }

  static BehaviorAction decode(Map<String, dynamic> json) {
    final rawType = (json['type'] as String?)?.trim() ?? '';
    final codec = _codecs[rawType];
    if (codec == null) {
      throw FormatException(
        'Type d’action de comportement inconnu: "$rawType"',
      );
    }
    return codec(json);
  }
}

/// Comportement attaché à un composant.
@immutable
class ComponentBehavior {
  const ComponentBehavior({
    required this.id,
    this.trigger = BehaviorTrigger.click,
    required this.action,
    this.enabled = true,
  });

  final String id;
  final BehaviorTrigger trigger;
  final BehaviorAction action;
  final bool enabled;

  Future<void> execute(
    BuildContext context, {
    BehaviorExecutionData? data,
  }) async {
    if (!enabled) return;
    if (data == null) {
      await action.execute(context);
    } else {
      await action.executeWithData(context, data);
    }
  }

  /// Valide les invariants des comportements déclaratifs d'info-bulle et d'état lié.
  void validate() {
    if (action case final TooltipAction tooltip) {
      tooltip.validate();
      if (trigger != BehaviorTrigger.hover) {
        throw const FormatException('onTooltip exige le déclencheur hover.');
      }
    } else if (trigger == BehaviorTrigger.hover) {
      throw const FormatException('hover exige une action onTooltip.');
    }
    if (action case final StateBindingAction stateBinding) {
      stateBinding.validate();
      if (trigger != BehaviorTrigger.binding) {
        throw const FormatException('bindState exige le déclencheur binding.');
      }
    }
  }

  Map<String, Object?> toJson() {
    validate();
    return {
      'id': id,
      'trigger': trigger.name,
      'enabled': enabled,
      'action': action.toJson(),
    };
  }

  /// Sérialisation compacte conservant le contrat du comportement.
  Map<String, Object?> toCompactJson() => {
    ...toJson(),
    if (action case final TooltipAction tooltip)
      'action': tooltip.toCompactJson(),
    if (action case final StateBindingAction stateBinding)
      'action': stateBinding.toCompactJson(),
  };

  factory ComponentBehavior.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String?) ?? '';
    final triggerName = (json['trigger'] as String?) ?? 'click';
    final trigger = BehaviorTrigger.values.firstWhere(
      (t) => t.name == triggerName,
      orElse: () => BehaviorTrigger.click,
    );
    final enabled = (json['enabled'] as bool?) ?? true;
    final actionJson = (json['action'] as Map<String, dynamic>?) ?? {};
    final action = BehaviorActionCatalog.decode(actionJson);

    final result = ComponentBehavior(
      id: id,
      trigger: trigger,
      action: action,
      enabled: enabled,
    );
    result.validate();
    return result;
  }

  ComponentBehavior copyWith({
    String? id,
    BehaviorTrigger? trigger,
    BehaviorAction? action,
    bool? enabled,
  }) => ComponentBehavior(
    id: id ?? this.id,
    trigger: trigger ?? this.trigger,
    action: action ?? this.action,
    enabled: enabled ?? this.enabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComponentBehavior &&
          other.id == id &&
          other.trigger == trigger &&
          other.action == action &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, trigger, action, enabled);
}

/// Élément du catalogue de comportements proposés à l'utilisateur.
@immutable
class BehaviorCatalogItem {
  const BehaviorCatalogItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.trigger,
    required this.actionType,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final BehaviorTrigger trigger;
  final String actionType;
}

/// Catalogue global des comportements disponibles.
abstract final class BehaviorCatalog {
  static const goToPage = BehaviorCatalogItem(
    id: 'go_to_page',
    title: 'Aller à la page',
    description: 'Naviguer vers une page au clic sur le composant',
    icon: Icons.alt_route,
    trigger: BehaviorTrigger.click,
    actionType: 'goToPage',
  );

  static const emitEvent = BehaviorCatalogItem(
    id: 'emit_event',
    title: 'Emettre un evenement',
    description: 'Publier un evenement interne au clic ou double-clic',
    icon: Icons.bolt,
    trigger: BehaviorTrigger.click,
    actionType: 'emitEvent',
  );

  static const zoneSize = BehaviorCatalogItem(
    id: 'zone_size',
    title: 'Taille de zone liée',
    description:
        'Ouvrir, fermer ou redimensionner une zone du layout avec une '
        'valeur numérique d’un repository, en l’animant',
    icon: Icons.width_normal_outlined,
    trigger: BehaviorTrigger.binding,
    actionType: 'bindZoneSize',
  );

  /// Comportement réactif changeant l'état (invisible, lecture seule, inactif) selon un booléen lié.
  static const bindState = BehaviorCatalogItem(
    id: 'bind_state',
    title: 'État lié (invisible, lecture seule, inactif)',
    description: 'Rendre le composant invisible, en lecture seule ou inactif selon un booléen d’un repository',
    icon: Icons.toggle_on_outlined,
    trigger: BehaviorTrigger.binding,
    actionType: 'bindState',
  );

  /// Comportement disponible pour toute cible, sans restriction de type.
  static const onTooltip = BehaviorCatalogItem(
    id: 'onTooltip',
    title: 'Afficher une info-bulle',
    description: 'Afficher un texte fixe ou lié à un repository au survol',
    icon: Icons.info_outline,
    trigger: BehaviorTrigger.hover,
    actionType: 'onTooltip',
  );

  static final List<BehaviorCatalogItem> items = [
    goToPage,
    emitEvent,
    zoneSize,
    bindState,
    onTooltip,
  ];
}
