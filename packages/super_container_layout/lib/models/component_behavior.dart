/// Modélisation des comportements interactifs ([ComponentBehavior]) attachés aux composants.
///
/// Associe un déclencheur ([BehaviorTrigger], ex. clic) à une action polymorphe
/// ([BehaviorAction], telle que la navigation [GoToPageAction]), stockée dans
/// `Appearance.behaviors`.
///
/// Les actions concrètes vivent dans `models/behaviours/` et sont réexportées ici :
/// - [AddArrayItemAction] (`behaviours/add_array_item_action.dart`)
/// - [CreationDefaultAction] (`behaviours/creation_default_action.dart`)
/// - [DatasourceAction] (`behaviours/datasource_action.dart`)
/// - [EmitEventAction] (`behaviours/emit_event_action.dart`)
/// - [GoToPageAction] (`behaviours/go_to_page_action.dart`)
/// - [SearchProviderAction] (`behaviours/search_provider_action.dart`)
/// - [RunJavaScriptAction] (`behaviours/run_javascript_action.dart`)
/// - [StateBindingAction] (`behaviours/state_binding_action.dart`)
/// - [TooltipAction] (`behaviours/tooltip_action.dart`)
/// - [ZoneSizeBindingAction] (`behaviours/zone_size_binding_action.dart`)
library;

import 'package:material_ui/material_ui.dart';

import '../services/events/super_event_bus.dart';
import 'behaviours/add_array_item_action.dart';
import 'behaviours/creation_default_action.dart';
import 'behaviours/datasource_action.dart';
import 'behaviours/emit_event_action.dart';
import 'behaviours/generate_pdf_action.dart';
import 'behaviours/go_to_page_action.dart';
import 'behaviours/search_provider_action.dart';
import 'behaviours/run_javascript_action.dart';
import 'behaviours/state_binding_action.dart';
import 'behaviours/tooltip_action.dart';
import 'behaviours/zone_size_binding_action.dart';

export 'behaviours/add_array_item_action.dart';
export 'behaviours/creation_default_action.dart';
export 'behaviours/datasource_action.dart';
export 'behaviours/emit_event_action.dart';
export 'behaviours/generate_pdf_action.dart';
export 'behaviours/go_to_page_action.dart';
export 'behaviours/search_provider_action.dart';
export 'behaviours/run_javascript_action.dart';
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
  binding('Liaison', 'Quand la valeur liée change', Icons.link),

  /// Comportement déclaratif : valeur par défaut lors de la création d'une ligne.
  create('Création', 'À la création d’une ligne', Icons.add_box_outlined);

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
    'searchProvider': SearchProviderAction.fromJson,
    'datasource': DatasourceAction.fromJson,
    'generatePdf': GeneratePdfAction.fromJson,
    'addArrayItem': AddArrayItemAction.fromJson,
    'creationDefault': CreationDefaultAction.fromJson,
    'runJavaScript': RunJavaScriptAction.fromJson,
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

  /// Valide les invariants des comportements déclaratifs d'info-bulle, d'état lié et de recherche.
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
    if (action case final SearchProviderAction search) {
      search.validate();
      if (!BehaviorTrigger.gestures.contains(trigger)) {
        throw const FormatException(
          'searchProvider exige le déclencheur click ou doubleClick.',
        );
      }
    }
    if (action case final DatasourceAction datasource) {
      datasource.validate();
      if (!BehaviorTrigger.gestures.contains(trigger)) {
        throw const FormatException(
          'datasource exige le déclencheur click ou doubleClick.',
        );
      }
    }
    if (action case final GeneratePdfAction pdf) {
      pdf.validate();
      if (!BehaviorTrigger.gestures.contains(trigger)) {
        throw const FormatException(
          'generatePdf exige le déclencheur click ou doubleClick.',
        );
      }
    }
    if (action case final AddArrayItemAction addArray) {
      addArray.validate();
      if (!BehaviorTrigger.gestures.contains(trigger)) {
        throw const FormatException(
          'addArrayItem exige le déclencheur click ou doubleClick.',
        );
      }
    }
    if (action case final CreationDefaultAction creationDefault) {
      creationDefault.validate();
      if (trigger != BehaviorTrigger.create) {
        throw const FormatException(
          'creationDefault exige le déclencheur create.',
        );
      }
    } else if (trigger == BehaviorTrigger.create) {
      throw const FormatException('create exige une action creationDefault.');
    }
    if (action case final RunJavaScriptAction script) {
      script.validate();
      if (!BehaviorTrigger.gestures.contains(trigger)) {
        throw const FormatException(
          'runJavaScript exige le déclencheur click ou doubleClick.',
        );
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
    if (action case final AddArrayItemAction addArray)
      'action': addArray.toCompactJson(),
    if (action case final CreationDefaultAction creationDefault)
      'action': creationDefault.toCompactJson(),
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

  /// Lance un provider de données (appel d'API, etc.) qui alimente un repository.
  static const searchProvider = BehaviorCatalogItem(
    id: 'search_provider',
    title: 'Lancer une recherche (provider)',
    description:
        'Lancer un provider de données, par exemple un appel d’API, qui '
        'alimente un repository à partir d’un repository de filtre',
    icon: Icons.manage_search_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'searchProvider',
  );

  /// Lance une commande de datasource (recherche, page, tri, CRUD).
  static const datasource = BehaviorCatalogItem(
    id: 'datasource',
    title: 'Commande de datasource',
    description:
        'Rechercher, paginer, trier, ou créer, lire, mettre à jour et '
        'supprimer l’entité courante d’une datasource',
    icon: Icons.dataset_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'datasource',
  );

  /// Génère un PDF A4 depuis la page A4 courante ou une page A4 du catalogue.
  static const generatePdf = BehaviorCatalogItem(
    id: 'generate_pdf',
    title: 'Générer un PDF (A4)',
    description: 'Exporter une page Document A4 au format PDF (aperçu/impression ou fichier)',
    icon: Icons.picture_as_pdf_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'generatePdf',
  );

  /// Ajoute une ligne dans un tableau JSON en s'appuyant sur son JSON Schema.
  static const addArrayItem = BehaviorCatalogItem(
    id: 'add_array_item',
    title: 'Ajouter une ligne (JSON Schema)',
    description:
        'Créer et ajouter une nouvelle ligne dans un tableau de repository '
        'selon son JSON Schema et les valeurs par défaut des SuperValue',
    icon: Icons.playlist_add_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'addArrayItem',
  );

  /// Définit la valeur par défaut d'une SuperValue lors de la création de ligne.
  static const creationDefault = BehaviorCatalogItem(
    id: 'creation_default',
    title: 'Valeur par défaut à la création',
    description:
        'Appliquer une valeur par défaut sur cette SuperValue lorsqu’une '
        'nouvelle ligne est créée dans le tableau lié',
    icon: Icons.add_box_outlined,
    trigger: BehaviorTrigger.create,
    actionType: 'creationDefault',
  );

  /// Exécute un script JavaScript au clic ou double-clic.
  static const runJavaScript = BehaviorCatalogItem(
    id: 'run_javascript',
    title: 'Script JavaScript (écriture repository)',
    description:
        'Exécuter un script au clic ; les écritures passent par ctx.set',
    icon: Icons.code,
    trigger: BehaviorTrigger.click,
    actionType: 'runJavaScript',
  );

  static final List<BehaviorCatalogItem> items = [
    goToPage,
    generatePdf,
    emitEvent,
    zoneSize,
    bindState,
    onTooltip,
    searchProvider,
    datasource,
    addArrayItem,
    creationDefault,
    runJavaScript,
  ];
}
