/// Modélisation des comportements interactifs ([ComponentBehavior]) attachés aux composants.
///
/// Associe un déclencheur ([BehaviorTrigger], ex. clic) à une action polymorphe
/// ([BehaviorAction], telle que la navigation [GoToPageAction]), stockée dans
/// `Appearance.behaviors`.
library;

import 'dart:convert';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../super_app.dart';
import '../services/events/super_event_bus.dart';

/// Déclencheur d'un comportement sur un composant.
enum BehaviorTrigger {
  click('Clic', 'Sur un clic', Icons.touch_app_outlined),
  doubleClick('Double-clic', 'Sur un double-clic', Icons.touch_app_outlined);

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

/// Publie un evenement interne avec les donnees automatiques et personnalisees.
@immutable
class EmitEventAction extends BehaviorAction {
  EmitEventAction({
    required this.eventId,
    Map<String, Object?> custom = const {},
  }) : custom = immutableEventJson(custom) {
    if (eventId.trim().isEmpty || eventId != eventId.trim()) {
      throw ArgumentError.value(
        eventId,
        'eventId',
        'Expected a non-empty ID without surrounding whitespace.',
      );
    }
  }

  final String eventId;
  final Map<String, Object?> custom;

  @override
  String get type => 'emitEvent';
  @override
  String get label => 'Emettre un evenement';
  @override
  String get description => eventId;
  @override
  IconData get icon => Icons.bolt;

  @override
  Future<void> execute(BuildContext context) async {
    throw StateError('EmitEventAction requires component execution data.');
  }

  @override
  Future<void> executeWithData(
    BuildContext context,
    BehaviorExecutionData data,
  ) async {
    final bus = SuperApp.maybeOf(context)?.eventBus;
    if (bus == null) {
      throw StateError('EmitEventAction requires SuperApp.eventBus.');
    }
    bus.emit(
      SuperComponentEvent(
        eventId: eventId,
        componentId: data.componentId,
        componentType: data.componentType,
        trigger: data.trigger.name,
        data: data.data,
        custom: custom,
      ),
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'eventId': eventId,
    'custom': custom,
  };

  factory EmitEventAction.fromJson(Map<String, dynamic> json) =>
      EmitEventAction(
        eventId: json['eventId'] as String,
        custom: (json['custom'] as Map<String, dynamic>?) ?? const {},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmitEventAction &&
          other.eventId == eventId &&
          jsonEncode(other.custom) == jsonEncode(custom);

  @override
  int get hashCode => Object.hash(eventId, jsonEncode(custom));
}

/// Action de navigation vers une page.
@immutable
class GoToPageAction extends BehaviorAction {
  const GoToPageAction({required this.pagePath, this.pageId, this.pageName});

  final String pagePath;
  final String? pageId;
  final String? pageName;

  @override
  String get type => 'goToPage';

  @override
  String get label => 'Aller à la page';

  @override
  String get description => pageName != null && pageName!.trim().isNotEmpty
      ? '$pageName ($pagePath)'
      : pagePath;

  @override
  IconData get icon => Icons.alt_route;

  @override
  Future<void> execute(BuildContext context) async {
    final path = pagePath.trim();
    if (path.isEmpty) return;

    final app = SuperApp.maybeOf(context);
    if (app?.pageRouting != null) {
      app!.pageRouting!.router.go(path);
      return;
    }
    if (app != null) {
      app.router.go(path);
      return;
    }
    GoRouter.maybeOf(context)?.go(path);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'pagePath': pagePath,
    if (pageId != null) 'pageId': pageId,
    if (pageName != null) 'pageName': pageName,
  };

  factory GoToPageAction.fromJson(Map<String, dynamic> json) {
    final path = (json['pagePath'] ?? json['path'] ?? '') as String;
    return GoToPageAction(
      pagePath: path,
      pageId: json['pageId'] as String?,
      pageName: json['pageName'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoToPageAction &&
          other.pagePath == pagePath &&
          other.pageId == pageId &&
          other.pageName == pageName;

  @override
  int get hashCode => Object.hash(pagePath, pageId, pageName);
}

/// Registre extensible pour décoder les actions polymorphes.
abstract final class BehaviorActionCatalog {
  static final Map<String, BehaviorAction Function(Map<String, dynamic> json)>
  _codecs = {
    'goToPage': GoToPageAction.fromJson,
    'emitEvent': EmitEventAction.fromJson,
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

  Map<String, Object?> toJson() => {
    'id': id,
    'trigger': trigger.name,
    'enabled': enabled,
    'action': action.toJson(),
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

    return ComponentBehavior(
      id: id,
      trigger: trigger,
      action: action,
      enabled: enabled,
    );
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

  static final List<BehaviorCatalogItem> items = [goToPage, emitEvent];
}
