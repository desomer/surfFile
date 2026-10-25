import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../super_app.dart';

/// Déclencheur d'un comportement sur un composant.
enum BehaviorTrigger {
  click('Clic', 'Sur un clic', Icons.touch_app_outlined);

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
  _codecs = {'goToPage': GoToPageAction.fromJson};

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

  Future<void> execute(BuildContext context) async {
    if (!enabled) return;
    await action.execute(context);
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

  static final List<BehaviorCatalogItem> items = [goToPage];
}
