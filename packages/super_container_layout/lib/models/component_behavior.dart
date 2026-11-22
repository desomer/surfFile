/// Modélisation des comportements interactifs ([ComponentBehavior]) attachés aux composants.
///
/// Associe trois paramètres explicites stockés dans `Appearance.behaviors` :
/// 1. L'événement déclencheur ([BehaviorEvent], ex. `onTap`, `onDoubleTap`, `onSelected`, `onChanged`) ;
/// 2. L'action polymorphe à lancer ([BehaviorAction], telle que [GoToPageAction]) ;
/// 3. Le validateur optionnel ([BehaviorValidator], ex. `isEmpty`, `isFill`, `otherIsEmpty`, `otherIsFill`)
///    qui décide si l'action doit réellement être exécutée.
///
/// Les éléments concrets vivent dans `models/behaviours/` et sont réexportés ici :
/// - [BehaviorEvent] / [BehaviorTrigger] (`behaviours/behavior_event.dart`)
/// - [BehaviorValidator] (`behaviours/behavior_validator.dart`)
/// - [AddArrayItemAction] (`behaviours/add_array_item_action.dart`)
/// - [CopyToClipboardAction] (`behaviours/copy_to_clipboard_action.dart`)
/// - [CreationDefaultAction] (`behaviours/creation_default_action.dart`)
/// - [DatasourceAction] (`behaviours/datasource_action.dart`)
/// - [EmitEventAction] (`behaviours/emit_event_action.dart`)
/// - [FilterCollectionAction] (`behaviours/filter_collection_action.dart`)
/// - [GoBackAction] (`behaviours/go_back_action.dart`)
/// - [GoToPageAction] (`behaviours/go_to_page_action.dart`)
/// - [RemoveArrayItemAction] (`behaviours/remove_array_item_action.dart`)
/// - [SearchProviderAction] (`behaviours/search_provider_action.dart`)
/// - [ShowMessageAction] (`behaviours/show_message_action.dart`)
/// - [SortCollectionAction] (`behaviours/sort_collection_action.dart`)
/// - [RunJavaScriptAction] (`behaviours/run_javascript_action.dart`)
/// - [BehaviorStylePatch] (`behaviours/behavior_style_patch.dart`)
/// - [SetStyleAction] (`behaviours/set_style_action.dart`)
/// - [SetVisibilityAction] (`behaviours/set_visibility_action.dart`)
/// - [SetStateAction] (`behaviours/set_state_action.dart`)
/// - [StateBindingAction] (`behaviours/state_binding_action.dart`)
/// - [TooltipAction] (`behaviours/tooltip_action.dart`)
/// - [ZoneSizeBindingAction] (`behaviours/zone_size_binding_action.dart`)
library;

import 'package:material_ui/material_ui.dart';

import '../services/events/super_event_bus.dart';
import 'behaviours/add_array_item_action.dart';
import 'behaviours/behavior_event.dart';
import 'behaviours/behavior_style_patch.dart';
import 'behaviours/behavior_validator.dart';
import 'behaviours/copy_to_clipboard_action.dart';
import 'behaviours/creation_default_action.dart';
import 'behaviours/datasource_action.dart';
import 'behaviours/emit_event_action.dart';
import 'behaviours/filter_collection_action.dart';
import 'behaviours/generate_pdf_action.dart';
import 'behaviours/go_back_action.dart';
import 'behaviours/go_to_page_action.dart';
import 'behaviours/remove_array_item_action.dart';
import 'behaviours/search_provider_action.dart';
import 'behaviours/show_message_action.dart';
import 'behaviours/sort_collection_action.dart';
import 'behaviours/run_javascript_action.dart';
import 'behaviours/set_state_action.dart';
import 'behaviours/set_style_action.dart';
import 'behaviours/set_visibility_action.dart';
import 'behaviours/state_binding_action.dart';
import 'behaviours/tooltip_action.dart';
import 'behaviours/zone_size_binding_action.dart';

export 'behaviours/add_array_item_action.dart';
export 'behaviours/behavior_event.dart';
export 'behaviours/behavior_style_patch.dart';
export 'behaviours/behavior_validator.dart';
export 'behaviours/copy_to_clipboard_action.dart';
export 'behaviours/creation_default_action.dart';
export 'behaviours/datasource_action.dart';
export 'behaviours/emit_event_action.dart';
export 'behaviours/filter_collection_action.dart';
export 'behaviours/generate_pdf_action.dart';
export 'behaviours/go_back_action.dart';
export 'behaviours/go_to_page_action.dart';
export 'behaviours/remove_array_item_action.dart';
export 'behaviours/search_provider_action.dart';
export 'behaviours/show_message_action.dart';
export 'behaviours/sort_collection_action.dart';
export 'behaviours/run_javascript_action.dart';
export 'behaviours/set_state_action.dart';
export 'behaviours/set_style_action.dart';
export 'behaviours/set_visibility_action.dart';
export 'behaviours/state_binding_action.dart';
export 'behaviours/tooltip_action.dart';
export 'behaviours/zone_size_binding_action.dart';

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

  /// Identifiants d'autres composants référencés par cette action (ex. `targetComponentId`).
  Set<String> get referencedComponentIds => const {};

  /// Remplace les identifiants de composants référencés lors d'une duplication.
  BehaviorAction remapComponentIds(Map<String, String> idMap) => this;
}

/// Metadonnees runtime de l'instance ayant declenche un comportement.
@immutable
class BehaviorExecutionData {
  BehaviorExecutionData({
    required this.componentId,
    required this.componentType,
    BehaviorEvent? event,
    BehaviorEvent? trigger,
    Map<String, Object?> data = const {},
  }) : assert(
         event != null || trigger != null,
         'Renseignez event ou trigger.',
       ),
       assert(
         event == null || trigger == null || event == trigger,
         'event et trigger doivent être identiques lorsqu’ils sont tous deux fournis.',
       ),
       event = event ?? trigger!,
       data = immutableEventJson(data);

  final String componentId;
  final String componentType;

  /// Événement ayant déclenché le comportement.
  final BehaviorEvent event;

  /// Alias de compatibilité vers [event].
  BehaviorEvent get trigger => event;

  final Map<String, Object?> data;
}

/// Registre extensible pour décoder les actions polymorphes.
abstract final class BehaviorActionCatalog {
  static final Map<String, BehaviorAction Function(Map<String, dynamic> json)>
  _codecs = {
    'goToPage': GoToPageAction.fromJson,
    'goBack': GoBackAction.fromJson,
    'emitEvent': EmitEventAction.fromJson,
    'bindZoneSize': ZoneSizeBindingAction.fromJson,
    'bindState': StateBindingAction.fromJson,
    'onTooltip': TooltipAction.fromJson,
    'searchProvider': SearchProviderAction.fromJson,
    'datasource': DatasourceAction.fromJson,
    'generatePdf': GeneratePdfAction.fromJson,
    'addArrayItem': AddArrayItemAction.fromJson,
    'removeArrayItem': RemoveArrayItemAction.fromJson,
    'creationDefault': CreationDefaultAction.fromJson,
    'runJavaScript': RunJavaScriptAction.fromJson,
    'sortCollection': SortCollectionAction.fromJson,
    'filterCollection': FilterCollectionAction.fromJson,
    'setStyle': SetStyleAction.fromJson,
    'setVisibility': SetVisibilityAction.fromJson,
    'setState': SetStateAction.fromJson,
    'showMessage': ShowMessageAction.fromJson,
    'copyToClipboard': CopyToClipboardAction.fromJson,
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

/// Comportement attaché à un composant : associe un événement ([event]),
/// un validateur optionnel ([validator]) et une action ([action]).
@immutable
class ComponentBehavior {
  const ComponentBehavior({
    required this.id,
    BehaviorEvent? event,
    BehaviorEvent? trigger,
    required this.action,
    this.elseAction,
    this.validator,
    this.enabled = true,
    this.debounceMs,
  }) : assert(
         event == null || trigger == null || event == trigger,
         'event et trigger doivent être identiques lorsqu’ils sont tous deux fournis.',
       ),
       event = event ?? trigger ?? BehaviorEvent.onTap;

  final String id;

  /// Événement déclencheur du comportement.
  final BehaviorEvent event;

  /// Alias de compatibilité vers [event].
  BehaviorEvent get trigger => event;

  /// Action lancée lorsque l'événement survient et que [validator] est satisfait.
  final BehaviorAction action;

  /// Action de repli exécutée lorsque [validator] s'évalue à `false`.
  final BehaviorAction? elseAction;

  /// Condition de garde optionnelle évaluée avant l'exécution de [action].
  ///
  /// Lorsque `null`, l'action s'exécute sans condition préalable.
  final BehaviorValidator? validator;

  final bool enabled;

  /// Délai optionnel de temporisation anti-rebond (en ms, `>= 0`) pour les événements impératifs.
  final int? debounceMs;

  /// Exécute directement [action] si [enabled] vaut `true`.
  ///
  /// Pour évaluer [validator] et bénéficier de la garde d'édition / anti-boucle,
  /// utiliser `BehaviorDispatcher.dispatch`.
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

  /// Remplace les identifiants de composants référencés dans [validator], [action] et [elseAction].
  ComponentBehavior remapComponentIds(Map<String, String> idMap) {
    if (idMap.isEmpty) return this;
    final remappedValidator = validator?.remapComponentIds(idMap);
    final remappedAction = action.remapComponentIds(idMap);
    final remappedElseAction = elseAction?.remapComponentIds(idMap);
    if (remappedValidator == validator &&
        remappedAction == action &&
        remappedElseAction == elseAction) {
      return this;
    }
    return copyWith(
      validator: remappedValidator,
      action: remappedAction,
      elseAction: remappedElseAction,
    );
  }

  /// Valide la cohérence entre [event], [action], [elseAction], [debounceMs] et [validator].
  void validate() {
    validator?.validate();

    if (debounceMs != null) {
      if (debounceMs! < 0) {
        throw const FormatException(
          'Le délai debounceMs d’un comportement doit être supérieur ou égal à 0.',
        );
      }
      if (debounceMs! > 0 && !event.isImperative) {
        throw FormatException(
          'debounceMs est réservé aux événements impératifs (reçu : ${event.name}).',
        );
      }
    }

    _validatePrimaryAction();
    _validateElseAction();
  }

  void _validatePrimaryAction() {
    if (action case final TooltipAction tooltip) {
      tooltip.validate();
      if (event != BehaviorEvent.onHover) {
        throw const FormatException('onTooltip exige l’événement onHover.');
      }
      return;
    } else if (event == BehaviorEvent.onHover) {
      throw const FormatException(
        'onHover est réservé à l’action onTooltip (utilisez onHoverEnter pour une action impérative).',
      );
    }

    if (action case final StateBindingAction stateBinding) {
      stateBinding.validate();
      if (event != BehaviorEvent.onBinding) {
        throw const FormatException('bindState exige l’événement onBinding.');
      }
      return;
    }

    if (action case final ZoneSizeBindingAction zoneSize) {
      zoneSize.binding.validate();
      if (event != BehaviorEvent.onBinding) {
        throw const FormatException('bindZoneSize exige l’événement onBinding.');
      }
      return;
    }

    if (action case final SortCollectionAction sortCollection) {
      if (event == BehaviorEvent.onBinding) {
        sortCollection.validate(declarative: true);
        return;
      }
      if (!event.isImperative) {
        throw FormatException(
          'L’action "sortCollection" exige onBinding ou un événement impératif (reçu : ${event.name}).',
        );
      }
      sortCollection.validate(declarative: false);
      return;
    }

    if (action case final FilterCollectionAction filterCollection) {
      if (event == BehaviorEvent.onBinding) {
        filterCollection.validate(
          declarative: true,
          hasBehaviorValidator: validator != null,
        );
        return;
      }
      if (!event.isImperative) {
        throw FormatException(
          'L’action "filterCollection" exige onBinding ou un événement impératif (reçu : ${event.name}).',
        );
      }
      filterCollection.validate(
        declarative: false,
        hasBehaviorValidator: validator != null,
      );
      return;
    }

    if (event == BehaviorEvent.onBinding) {
      throw const FormatException(
        'onBinding est réservé aux actions réactives bindState, bindZoneSize, sortCollection et filterCollection.',
      );
    }

    if (action case final CreationDefaultAction creationDefault) {
      creationDefault.validate();
      if (event != BehaviorEvent.onCreate) {
        throw const FormatException(
          'creationDefault exige l’événement onCreate.',
        );
      }
      return;
    } else if (event == BehaviorEvent.onCreate) {
      throw const FormatException(
        'onCreate est réservé à l’action creationDefault.',
      );
    }

    // Actions impératives : autorisées sur tout événement impératif.
    if (!event.isImperative) {
      throw FormatException(
        'L’action "${action.type}" exige un événement impératif (reçu : ${event.name}).',
      );
    }
    _validateImperativeAction(action);
  }

  void _validateElseAction() {
    final fallback = elseAction;
    if (fallback == null) return;
    if (validator == null) {
      throw const FormatException('elseAction exige un validateur (validator).');
    }
    if (!event.isImperative) {
      throw FormatException(
        'elseAction exige un événement impératif (reçu : ${event.name}).',
      );
    }
    if (fallback is TooltipAction ||
        fallback is StateBindingAction ||
        fallback is ZoneSizeBindingAction ||
        fallback is CreationDefaultAction) {
      throw FormatException(
        'L’action déclarative "${fallback.type}" ne peut pas être utilisée comme elseAction.',
      );
    }
    _validateImperativeAction(fallback);
  }

  void _validateImperativeAction(BehaviorAction act) {
    if (act case final GoBackAction goBack) {
      goBack.validate();
    } else if (act case final SearchProviderAction search) {
      search.validate();
    } else if (act case final DatasourceAction datasource) {
      datasource.validate();
    } else if (act case final GeneratePdfAction pdf) {
      pdf.validate();
    } else if (act case final AddArrayItemAction addArray) {
      addArray.validate();
    } else if (act case final RemoveArrayItemAction removeArray) {
      removeArray.validate();
    } else if (act case final RunJavaScriptAction script) {
      script.validate();
    } else if (act case final SetStyleAction setStyle) {
      setStyle.validate();
    } else if (act case final SetVisibilityAction setVisibility) {
      setVisibility.validate();
    } else if (act case final SetStateAction setState) {
      setState.validate();
    } else if (act case final ShowMessageAction showMessage) {
      showMessage.validate();
    } else if (act case final CopyToClipboardAction copyToClipboard) {
      copyToClipboard.validate();
    } else if (act case final SortCollectionAction sortCollection) {
      sortCollection.validate(declarative: false);
    } else if (act case final FilterCollectionAction filterCollection) {
      filterCollection.validate(
        declarative: false,
        hasBehaviorValidator: validator != null,
      );
    }
  }

  static Map<String, Object?> _actionToCompactJson(BehaviorAction act) =>
      switch (act) {
        final TooltipAction tooltip => tooltip.toCompactJson(),
        final StateBindingAction stateBinding => stateBinding.toCompactJson(),
        final GoBackAction goBack => goBack.toCompactJson(),
        final AddArrayItemAction addArray => addArray.toCompactJson(),
        final RemoveArrayItemAction removeArray => removeArray.toCompactJson(),
        final CreationDefaultAction creationDefault =>
          creationDefault.toCompactJson(),
        final SetStyleAction setStyle => setStyle.toCompactJson(),
        final SetVisibilityAction setVisibility =>
          setVisibility.toCompactJson(),
        final SetStateAction setState => setState.toCompactJson(),
        final SortCollectionAction sortCollection =>
          sortCollection.toCompactJson(),
        final FilterCollectionAction filterCollection =>
          filterCollection.toCompactJson(),
        final ShowMessageAction showMessage => showMessage.toCompactJson(),
        final CopyToClipboardAction copyToClipboard =>
          copyToClipboard.toCompactJson(),
        _ => act.toJson(),
      };

  Map<String, Object?> toJson() {
    validate();
    return {
      'id': id,
      'event': event.name,
      'enabled': enabled,
      if (validator != null) 'validator': validator!.toJson(),
      'action': action.toJson(),
      if (elseAction != null) 'elseAction': elseAction!.toJson(),
      'debounceMs': ?debounceMs,
    };
  }

  /// Sérialisation compacte conservant le contrat du comportement.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      'id': id,
      'event': event.name,
      if (!enabled) 'enabled': enabled,
      if (validator != null) 'validator': validator!.toCompactJson(),
      'action': _actionToCompactJson(action),
      if (elseAction != null) 'elseAction': _actionToCompactJson(elseAction!),
      if (debounceMs != null && debounceMs! > 0) 'debounceMs': debounceMs!,
    };
  }

  factory ComponentBehavior.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String?) ?? '';
    final rawEvent = json.containsKey('event')
        ? json['event']
        : json['trigger'];
    final event = BehaviorEvent.fromJson(rawEvent);
    final enabled = (json['enabled'] as bool?) ?? true;
    final rawValidator = json['validator'];
    BehaviorValidator? validator;
    if (rawValidator != null) {
      if (rawValidator is! Map) {
        throw const FormatException(
          'Le champ "validator" d’un comportement doit être un objet JSON.',
        );
      }
      validator = BehaviorValidatorCatalog.decode(
        Map<String, dynamic>.from(rawValidator),
      );
    }
    final actionJson = (json['action'] as Map<String, dynamic>?) ?? {};
    final action = BehaviorActionCatalog.decode(actionJson);

    final rawElseAction = json['elseAction'];
    BehaviorAction? elseAction;
    if (rawElseAction != null) {
      if (rawElseAction is! Map) {
        throw const FormatException(
          'Le champ "elseAction" d’un comportement doit être un objet JSON.',
        );
      }
      elseAction = BehaviorActionCatalog.decode(
        Map<String, dynamic>.from(rawElseAction),
      );
    }

    final rawDebounce = json['debounceMs'];
    if (rawDebounce != null && rawDebounce is! int) {
      throw const FormatException(
        'Le champ "debounceMs" d’un comportement doit être un entier.',
      );
    }

    final result = ComponentBehavior(
      id: id,
      event: event,
      action: action,
      elseAction: elseAction,
      validator: validator,
      enabled: enabled,
      debounceMs: rawDebounce as int?,
    );
    result.validate();
    return result;
  }

  ComponentBehavior copyWith({
    String? id,
    BehaviorEvent? event,
    BehaviorEvent? trigger,
    BehaviorAction? action,
    BehaviorAction? elseAction,
    bool clearElseAction = false,
    BehaviorValidator? validator,
    bool clearValidator = false,
    bool? enabled,
    int? debounceMs,
    bool clearDebounceMs = false,
  }) => ComponentBehavior(
    id: id ?? this.id,
    event: event ?? trigger ?? this.event,
    action: action ?? this.action,
    elseAction: clearElseAction ? null : (elseAction ?? this.elseAction),
    validator: clearValidator ? null : (validator ?? this.validator),
    enabled: enabled ?? this.enabled,
    debounceMs: clearDebounceMs ? null : (debounceMs ?? this.debounceMs),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComponentBehavior &&
          other.id == id &&
          other.event == event &&
          other.action == action &&
          other.elseAction == elseAction &&
          other.validator == validator &&
          other.enabled == enabled &&
          other.debounceMs == debounceMs;

  @override
  int get hashCode => Object.hash(
    id,
    event,
    action,
    elseAction,
    validator,
    enabled,
    debounceMs,
  );
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
    this.supportsBinding = false,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;

  /// Événement par défaut (ou exclusif si déclaratif) pour cette action.
  final BehaviorEvent trigger;

  /// Alias explicite de [trigger].
  BehaviorEvent get defaultEvent => trigger;

  final String actionType;

  /// Indique si cette action impérative peut aussi être attachée en mode déclaratif (`onBinding`).
  final bool supportsBinding;

  /// Indique si cette action est impérative (compatible avec tout événement impératif).
  bool get isImperative => trigger.isImperative;

  /// Indique si cette action peut être associée à [event].
  bool supportsEvent(BehaviorEvent event) => isImperative
      ? (event.isImperative || (supportsBinding && event == BehaviorEvent.onBinding))
      : event == trigger;
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

  /// Revient à la page précédente dans l'historique de navigation.
  static const goBack = BehaviorCatalogItem(
    id: 'go_back',
    title: 'Revenir en arrière',
    description: 'Revenir à la page précédente dans l’historique de navigation',
    icon: Icons.arrow_back,
    trigger: BehaviorTrigger.click,
    actionType: 'goBack',
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

  /// Modifie dynamiquement le style (couleurs, bordure, rayon, opacité, état nommé…) en mémoire.
  static const setStyle = BehaviorCatalogItem(
    id: 'set_style',
    title: 'Changer le style',
    description:
        'Modifier dynamiquement les couleurs, bordures, opacité, typographie '
        'ou l’état nommé de ce composant ou d’un autre composant',
    icon: Icons.palette_outlined,
    trigger: BehaviorEvent.onTap,
    actionType: 'setStyle',
  );

  /// Affiche, masque, bascule ou réinitialise la visibilité d'un composant en mémoire.
  static const setVisibility = BehaviorCatalogItem(
    id: 'set_visibility',
    title: 'Changer la visibilité',
    description:
        'Afficher, masquer ou basculer la visibilité de ce composant ou '
        'd’un autre composant',
    icon: Icons.visibility_outlined,
    trigger: BehaviorEvent.onTap,
    actionType: 'setVisibility',
  );

  /// Active, désactive (`disabled`) ou passe en lecture seule (`readOnly`) un composant en mémoire.
  static const setState = BehaviorCatalogItem(
    id: 'set_state',
    title: 'Changer l’état (inactif / lecture seule)',
    description:
        'Désactiver, réactiver ou passer en lecture seule ce composant ou '
        'un autre composant',
    icon: Icons.block_outlined,
    trigger: BehaviorEvent.onTap,
    actionType: 'setState',
  );

  /// Trie une collection (`SuperListView` ou `SuperTable`) en mode déclaratif ou impératif.
  static const sortCollection = BehaviorCatalogItem(
    id: 'sort_collection',
    title: 'Trier une liste ou un tableau',
    description:
        'Trier les lignes d’un SuperListView ou SuperTable selon un ou plusieurs champs',
    icon: Icons.sort,
    trigger: BehaviorEvent.onTap,
    actionType: 'sortCollection',
    supportsBinding: true,
  );

  /// Filtre une collection (`SuperListView` ou `SuperTable`) via un validateur.
  static const filterCollection = BehaviorCatalogItem(
    id: 'filter_collection',
    title: 'Filtrer une liste ou un tableau',
    description:
        'Filtrer les lignes d’un SuperListView ou SuperTable selon un validateur',
    icon: Icons.filter_list,
    trigger: BehaviorEvent.onTap,
    actionType: 'filterCollection',
    supportsBinding: true,
  );

  /// Supprime une ligne d'un tableau JSON dans un repository.
  static const removeArrayItem = BehaviorCatalogItem(
    id: 'remove_array_item',
    title: 'Supprimer une ligne',
    description:
        'Supprimer la ligne courante ou sélectionnée dans un tableau de repository',
    icon: Icons.playlist_remove_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'removeArrayItem',
  );

  /// Affiche un message temporaire (`SnackBar`) avec sévérité configurable.
  static const showMessage = BehaviorCatalogItem(
    id: 'show_message',
    title: 'Afficher un message',
    description:
        'Afficher une notification temporaire (info, succès, avertissement, erreur)',
    icon: Icons.feedback_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'showMessage',
  );

  /// Copie un texte statique, la valeur d'un composant ou d'une liaison dans le presse-papiers.
  static const copyToClipboard = BehaviorCatalogItem(
    id: 'copy_to_clipboard',
    title: 'Copier dans le presse-papiers',
    description:
        'Copier un texte, la valeur d’un composant ou d’un repository dans le presse-papiers',
    icon: Icons.content_copy_outlined,
    trigger: BehaviorTrigger.click,
    actionType: 'copyToClipboard',
  );

  static final List<BehaviorCatalogItem> items = [
    goToPage,
    goBack,
    generatePdf,
    emitEvent,
    setStyle,
    setVisibility,
    setState,
    showMessage,
    copyToClipboard,
    zoneSize,
    bindState,
    onTooltip,
    searchProvider,
    datasource,
    addArrayItem,
    removeArrayItem,
    creationDefault,
    runJavaScript,
    sortCollection,
    filterCollection,
  ];
}
