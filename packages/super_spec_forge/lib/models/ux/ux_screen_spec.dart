/// Modèles immuables des schémas directeurs d'écrans, zones spatiales, actions et états UX ([UxScreenSpec]).
library;

import 'package:flutter/foundation.dart';

/// Pattern d'architecture spatiale d'un écran applicatif.
enum UxScreenPattern {
  /// Volet maître latéral (liste/arbre) et fiche détail synchronisée en zone centrale.
  masterDetail('Maître / Détail'),

  /// Tableau de bord analytique (bandeau KPI en nord + graphiques/tableaux au centre).
  dashboard('Dashboard analytique'),

  /// Formulaire de saisie ou page de paramètres défilante.
  form('Formulaire / Saisie'),

  /// Explorateur tabulaire dense avec barre de filtres et d'actions en nord.
  tableExplorer('Explorateur tabulaire'),

  /// Assistant séquentiel multi-étapes.
  wizard('Assistant multi-étapes'),

  /// Tableau de flux visuel par colonnes d'état.
  kanban('Kanban / Flux'),

  /// Modèle de document paginé A4 destiné à l'aperçu et à l'export PDF.
  documentA4('Document PDF A4'),

  /// Agencement libre sur mesure.
  custom('Sur mesure');

  /// Construit un pattern d'écran UX.
  const UxScreenPattern(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un pattern d'écran depuis JSON ou un alias courant, avec repli sur [masterDetail].
  static UxScreenPattern fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final pattern in UxScreenPattern.values) {
        if (pattern.name.toLowerCase() == norm ||
            pattern.label.toLowerCase() == norm) {
          return pattern;
        }
      }
      switch (norm) {
        case 'master_detail':
        case 'master-detail':
        case 'maitre_detail':
        case 'split':
          return UxScreenPattern.masterDetail;
        case 'analytics':
        case 'kpi':
          return UxScreenPattern.dashboard;
        case 'form_view':
        case 'settings':
        case 'formulaire':
          return UxScreenPattern.form;
        case 'table_explorer':
        case 'table-explorer':
        case 'table':
        case 'list':
        case 'datagrid':
          return UxScreenPattern.tableExplorer;
        case 'stepper':
        case 'assistant':
          return UxScreenPattern.wizard;
        case 'board':
          return UxScreenPattern.kanban;
        case 'document_a4':
        case 'document-a4':
        case 'a4':
        case 'a4document':
        case 'pdf':
          return UxScreenPattern.documentA4;
        case 'free':
        case 'sur_mesure':
          return UxScreenPattern.custom;
      }
    }
    return UxScreenPattern.masterDetail;
  }
}

/// Zone cardinale d'un `SuperLayout` dans le blueprint d'écran.
enum UxLayoutZoneName {
  /// Bandeau supérieur (`north`).
  north('Nord'),

  /// Volet latéral gauche (`west`).
  west('Ouest'),

  /// Zone principale centrale (`center`).
  center('Centre'),

  /// Volet latéral droit / inspecteur (`east`).
  east('Est'),

  /// Bandeau ou barre d'actions inférieure (`south`).
  south('Sud');

  /// Construit un nom de zone cardinale.
  const UxLayoutZoneName(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout une zone depuis JSON ou un alias directionnel, avec repli sur [center].
  static UxLayoutZoneName fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final zone in UxLayoutZoneName.values) {
        if (zone.name.toLowerCase() == norm ||
            zone.label.toLowerCase() == norm) {
          return zone;
        }
      }
      switch (norm) {
        case 'top':
        case 'header':
          return UxLayoutZoneName.north;
        case 'left':
        case 'sidebar':
          return UxLayoutZoneName.west;
        case 'main':
        case 'body':
          return UxLayoutZoneName.center;
        case 'right':
        case 'inspector':
          return UxLayoutZoneName.east;
        case 'bottom':
        case 'footer':
          return UxLayoutZoneName.south;
      }
    }
    return UxLayoutZoneName.center;
  }
}

/// Famille sémantique d'un bloc d'interface placé dans une zone d'écran.
enum UxWidgetKind {
  /// Rangée d'indicateurs clés de performance (`Card` + `SuperValue`).
  kpiRow('Cartes KPI'),

  /// Tableau structuré multi-colonnes (`SuperTable`).
  dataTable('Tableau'),

  /// Liste maître sélectionnable (`SuperListView`).
  masterList('Liste maître'),

  /// Arborescence hiérarchique (`SuperTreeView`).
  treeView('Arborescence'),

  /// Carte de consultation détaillée (`Card` + champs liés `[?]`).
  detailCard('Fiche détail'),

  /// Groupe de champs de saisie (`Card` + `SuperValue` en mode `input`).
  formSection('Section de formulaire'),

  /// Conteneur à onglets (`SuperTab`).
  tabGroup('Groupe d’onglets'),

  /// Visualisation graphique (`SuperChart`).
  chart('Graphique'),

  /// Barre d'actions horizontale (`SuperAction`).
  toolbar('Barre d’outils'),

  /// Barre de recherche et filtres rapides.
  searchFilterBar('Recherche & Filtres'),

  /// Bandeau d'état métier, d'alerte ou de progression (`SuperIndicator`).
  statusBanner('Bandeau d’état');

  /// Construit un type sémantique de bloc UX.
  const UxWidgetKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout un type de bloc UX depuis JSON ou un alias courant, avec repli sur [detailCard].
  static UxWidgetKind fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final kind in UxWidgetKind.values) {
        if (kind.name.toLowerCase() == norm ||
            kind.label.toLowerCase() == norm) {
          return kind;
        }
      }
      switch (norm) {
        case 'kpi':
        case 'kpi_row':
        case 'kpi-row':
        case 'metrics':
          return UxWidgetKind.kpiRow;
        case 'table':
        case 'data_table':
        case 'data-table':
        case 'supertable':
          return UxWidgetKind.dataTable;
        case 'list':
        case 'listview':
        case 'master_list':
        case 'master-list':
        case 'superlistview':
          return UxWidgetKind.masterList;
        case 'tree':
        case 'tree_view':
        case 'tree-view':
        case 'supertreeview':
          return UxWidgetKind.treeView;
        case 'detail':
        case 'detail_card':
        case 'detail-card':
        case 'card':
          return UxWidgetKind.detailCard;
        case 'form':
        case 'form_section':
        case 'form-section':
        case 'inputs':
          return UxWidgetKind.formSection;
        case 'tabs':
        case 'tab_group':
        case 'tab-group':
        case 'supertab':
          return UxWidgetKind.tabGroup;
        case 'graph':
        case 'superchart':
          return UxWidgetKind.chart;
        case 'action_bar':
        case 'actions':
          return UxWidgetKind.toolbar;
        case 'search':
        case 'filter':
        case 'filters':
        case 'filter_bar':
        case 'search_filter_bar':
        case 'search-filter-bar':
          return UxWidgetKind.searchFilterBar;
        case 'banner':
        case 'status':
        case 'status_banner':
        case 'status-banner':
        case 'indicator':
          return UxWidgetKind.statusBanner;
      }
    }
    return UxWidgetKind.detailCard;
  }
}

/// Niveau de hiérarchie visuelle et d'engagement d'une action d'écran.
enum UxActionHierarchy {
  /// Action principale engageante de la vue (bouton `filled` unique).
  primary('Primaire'),

  /// Action complémentaire courante (bouton `tonal` ou `outlined`).
  secondary('Secondaire'),

  /// Action sensible ou irréversible nécessitant garde-fou/confirmation.
  destructive('Destructrice'),

  /// Action contextuelle discrète sur ligne ou barre d'icônes (`icon` / `text`).
  inline('En ligne / Icône');

  /// Construit un niveau de hiérarchie d'action.
  const UxActionHierarchy(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Résout une hiérarchie d'action depuis JSON ou un alias courant, avec repli sur [secondary].
  static UxActionHierarchy fromJson(Object? raw) {
    if (raw is String) {
      final norm = raw.trim().toLowerCase();
      for (final level in UxActionHierarchy.values) {
        if (level.name.toLowerCase() == norm ||
            level.label.toLowerCase() == norm) {
          return level;
        }
      }
      switch (norm) {
        case 'filled':
        case 'main':
        case 'cta':
          return UxActionHierarchy.primary;
        case 'tonal':
        case 'outlined':
        case 'tertiary':
          return UxActionHierarchy.secondary;
        case 'danger':
        case 'delete':
        case 'error':
          return UxActionHierarchy.destructive;
        case 'icon':
        case 'row':
        case 'text':
          return UxActionHierarchy.inline;
      }
    }
    return UxActionHierarchy.secondary;
  }
}

/// Emplacement fonctionnel d'un composant au sein d'une zone d'écran ([UxScreenZoneSpec]).
@immutable
class UxZoneWidgetSlot {
  /// Construit un emplacement de composant UX immuable.
  UxZoneWidgetSlot({
    required this.id,
    required this.title,
    this.kind = UxWidgetKind.detailCard,
    this.businessObjectId = '',
    List<String> attributeNames = const <String>[],
    this.summary = '',
  }) : attributeNames = List<String>.unmodifiable(attributeNames);

  /// Identifiant unique du slot dans la zone.
  final String id;

  /// Titre lisible du bloc fonctionnel.
  final String title;

  /// Type sémantique du composant SuperDesigner projeté.
  final UxWidgetKind kind;

  /// Identifiant ou nom technique du `BusinessObjectSpec` lié (optionnel).
  final String businessObjectId;

  /// Noms des attributs métiers affichés ou édités dans ce bloc.
  final List<String> attributeNames;

  /// Résumé fonctionnel ou consignes d'agencement du bloc.
  final String summary;

  /// Vérifie les invariants du slot.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'UxZoneWidgetSlot.id ne peut pas être vide.',
      );
    }
    if (title.trim().isEmpty) {
      throw const FormatException(
        'UxZoneWidgetSlot.title ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  UxZoneWidgetSlot copyWith({
    String? id,
    String? title,
    UxWidgetKind? kind,
    String? businessObjectId,
    List<String>? attributeNames,
    String? summary,
  }) => UxZoneWidgetSlot(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    businessObjectId: businessObjectId ?? this.businessObjectId,
    attributeNames: attributeNames ?? this.attributeNames,
    summary: summary ?? this.summary,
  );

  /// Sérialise le slot en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'kind': kind.name,
    'businessObjectId': businessObjectId,
    'attributeNames': attributeNames,
    'summary': summary,
  };

  /// Désérialise un slot depuis JSON avec valeurs de repli tolérantes.
  factory UxZoneWidgetSlot.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxZoneWidgetSlot doit être un objet JSON.');
    }
    final kind = UxWidgetKind.fromJson(raw['kind']);
    final rawTitle =
        (raw['title'] as String?)?.trim() ??
        (raw['name'] as String?)?.trim() ??
        '';
    final title = rawTitle.isEmpty ? kind.label : rawTitle;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final slot = UxZoneWidgetSlot(
      id: rawId.isEmpty ? 'slot_${title.hashCode.abs()}' : rawId,
      title: title,
      kind: kind,
      businessObjectId: (raw['businessObjectId'] as String?)?.trim() ?? '',
      attributeNames: _stringList(raw['attributeNames']),
      summary: (raw['summary'] as String?)?.trim() ?? '',
    );
    slot.validate();
    return slot;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxZoneWidgetSlot &&
          other.id == id &&
          other.title == title &&
          other.kind == kind &&
          other.businessObjectId == businessObjectId &&
          listEquals(other.attributeNames, attributeNames) &&
          other.summary == summary;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    businessObjectId,
    Object.hashAll(attributeNames),
    summary,
  );
}

/// Configuration spatiale d'une zone cardinale (`SuperLayout`) d'un écran UX.
@immutable
class UxScreenZoneSpec {
  /// Construit une zone d'écran immuable.
  UxScreenZoneSpec({
    required this.zone,
    this.enabled = true,
    this.sizePx,
    this.scrollable = false,
    this.axis = 'column',
    List<UxZoneWidgetSlot> slots = const <UxZoneWidgetSlot>[],
  }) : slots = List<UxZoneWidgetSlot>.unmodifiable(slots);

  /// Zone cardinale ciblée (`north`, `west`, `center`, `east`, `south`).
  final UxLayoutZoneName zone;

  /// Indique si la zone est active sur le layout de l'écran.
  final bool enabled;

  /// Taille fixe optionnelle en pixels pour les bords latéraux ou horizontaux (ex. `320` en `west`).
  final double? sizePx;

  /// Indique si le flux interne de la zone défile verticalement (`scrollable`).
  final bool scrollable;

  /// Axe de distribution des slots dans la zone (`'column'` ou `'row'`).
  final String axis;

  /// Blocs fonctionnels ordonnés contenus dans cette zone.
  final List<UxZoneWidgetSlot> slots;

  /// Vérifie les invariants de la zone et l'unicité des identifiants de slots.
  void validate() {
    if (axis != 'column' && axis != 'row') {
      throw FormatException(
        'UxScreenZoneSpec.axis doit valoir "column" ou "row" : $axis',
      );
    }
    if (sizePx != null && (!sizePx!.isFinite || sizePx! <= 0)) {
      throw FormatException(
        'UxScreenZoneSpec.sizePx doit être strictement positif : $sizePx',
      );
    }
    final slotIds = <String>{};
    for (final slot in slots) {
      slot.validate();
      if (!slotIds.add(slot.id)) {
        throw FormatException(
          'Slot UX dupliqué « ${slot.id} » dans la zone ${zone.name}.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  UxScreenZoneSpec copyWith({
    UxLayoutZoneName? zone,
    bool? enabled,
    double? sizePx,
    bool clearSizePx = false,
    bool? scrollable,
    String? axis,
    List<UxZoneWidgetSlot>? slots,
  }) => UxScreenZoneSpec(
    zone: zone ?? this.zone,
    enabled: enabled ?? this.enabled,
    sizePx: clearSizePx ? null : (sizePx ?? this.sizePx),
    scrollable: scrollable ?? this.scrollable,
    axis: axis ?? this.axis,
    slots: slots ?? this.slots,
  );

  /// Sérialise la zone en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'zone': zone.name,
    'enabled': enabled,
    if (sizePx != null) 'sizePx': sizePx,
    'scrollable': scrollable,
    'axis': axis,
    'slots': [for (final s in slots) s.toJson()],
  };

  /// Désérialise une zone d'écran depuis JSON avec normalisation tolérante.
  factory UxScreenZoneSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxScreenZoneSpec doit être un objet JSON.');
    }
    final rawSize = raw['sizePx'];
    final parsedSize = switch (rawSize) {
      final num v when v.isFinite && v > 0 => v.toDouble(),
      final String s => switch (double.tryParse(s.trim())) {
        final double v when v.isFinite && v > 0 => v,
        _ => null,
      },
      _ => null,
    };
    final rawAxis = (raw['axis'] as String?)?.trim().toLowerCase() ?? 'column';
    final axis = (rawAxis == 'row' || rawAxis == 'horizontal')
        ? 'row'
        : 'column';

    final parsedSlots = <UxZoneWidgetSlot>[];
    final seenSlotIds = <String>{};
    if (raw['slots'] is List) {
      for (final item in raw['slots'] as List) {
        var slot = UxZoneWidgetSlot.fromJson(item);
        if (!seenSlotIds.add(slot.id)) {
          var suffix = 2;
          while (!seenSlotIds.add('${slot.id}_$suffix')) {
            suffix++;
          }
          slot = slot.copyWith(id: '${slot.id}_$suffix');
        }
        parsedSlots.add(slot);
      }
    }

    final zoneSpec = UxScreenZoneSpec(
      zone: UxLayoutZoneName.fromJson(raw['zone']),
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : true,
      sizePx: parsedSize,
      scrollable: raw['scrollable'] == true,
      axis: axis,
      slots: parsedSlots,
    );
    zoneSpec.validate();
    return zoneSpec;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxScreenZoneSpec &&
          other.zone == zone &&
          other.enabled == enabled &&
          other.sizePx == sizePx &&
          other.scrollable == scrollable &&
          other.axis == axis &&
          listEquals(other.slots, slots);

  @override
  int get hashCode => Object.hash(
    zone,
    enabled,
    sizePx,
    scrollable,
    axis,
    Object.hashAll(slots),
  );
}

/// Action utilisateur exposée sur un écran et rattachée aux règles de gestion (`RG-xxx`).
@immutable
class UxScreenAction {
  /// Construit une action d'écran immuable.
  UxScreenAction({
    required this.id,
    required this.label,
    this.hierarchy = UxActionHierarchy.secondary,
    List<String> businessRuleIds = const <String>[],
    this.targetRouteId = '',
    this.confirmationMessage = '',
  }) : businessRuleIds = List<String>.unmodifiable(businessRuleIds);

  /// Identifiant unique de l'action sur l'écran.
  final String id;

  /// Libellé affiché sur le bouton ou en infobulle.
  final String label;

  /// Hiérarchie visuelle de l'action (`primary`, `secondary`, `destructive`, `inline`).
  final UxActionHierarchy hierarchy;

  /// Identifiants ou codes des règles de gestion (`RG-xxx`) déclenchées ou vérifiées.
  final List<String> businessRuleIds;

  /// Identifiant de la route ou modale ouverte suite à l'action (optionnel).
  final String targetRouteId;

  /// Message de confirmation exigé avant exécution (recommandé pour `destructive`).
  final String confirmationMessage;

  /// Vérifie les invariants de l'action.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UxScreenAction.id ne peut pas être vide.');
    }
    if (label.trim().isEmpty) {
      throw const FormatException(
        'UxScreenAction.label ne peut pas être vide.',
      );
    }
  }

  /// Retourne une copie modifiée.
  UxScreenAction copyWith({
    String? id,
    String? label,
    UxActionHierarchy? hierarchy,
    List<String>? businessRuleIds,
    String? targetRouteId,
    String? confirmationMessage,
  }) => UxScreenAction(
    id: id ?? this.id,
    label: label ?? this.label,
    hierarchy: hierarchy ?? this.hierarchy,
    businessRuleIds: businessRuleIds ?? this.businessRuleIds,
    targetRouteId: targetRouteId ?? this.targetRouteId,
    confirmationMessage: confirmationMessage ?? this.confirmationMessage,
  );

  /// Sérialise l'action en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'hierarchy': hierarchy.name,
    'businessRuleIds': businessRuleIds,
    'targetRouteId': targetRouteId,
    'confirmationMessage': confirmationMessage,
  };

  /// Désérialise une action d'écran depuis JSON avec valeurs de repli tolérantes.
  factory UxScreenAction.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxScreenAction doit être un objet JSON.');
    }
    final rawLabel =
        (raw['label'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        '';
    final label = rawLabel.isEmpty ? 'Action' : rawLabel;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final action = UxScreenAction(
      id: rawId.isEmpty ? 'act_${label.hashCode.abs()}' : rawId,
      label: label,
      hierarchy: UxActionHierarchy.fromJson(raw['hierarchy']),
      businessRuleIds: _stringList(raw['businessRuleIds']),
      targetRouteId: (raw['targetRouteId'] as String?)?.trim() ?? '',
      confirmationMessage:
          (raw['confirmationMessage'] as String?)?.trim() ?? '',
    );
    action.validate();
    return action;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxScreenAction &&
          other.id == id &&
          other.label == label &&
          other.hierarchy == hierarchy &&
          listEquals(other.businessRuleIds, businessRuleIds) &&
          other.targetRouteId == targetRouteId &&
          other.confirmationMessage == confirmationMessage;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    hierarchy,
    Object.hashAll(businessRuleIds),
    targetRouteId,
    confirmationMessage,
  );
}

/// Spécification des états transitoires, vides, d'erreur et de lecture seule d'un écran.
@immutable
class UxScreenStatesSpec {
  /// Construit une spécification d'états UX immuable.
  UxScreenStatesSpec({
    this.emptyStateTitle = '',
    this.emptyStateCta = '',
    this.loadingPattern = 'skeleton',
    this.errorHandling = '',
    List<String> readOnlyRuleIds = const <String>[],
  }) : readOnlyRuleIds = List<String>.unmodifiable(readOnlyRuleIds);

  /// Spécification d'états UX vide par défaut.
  static final UxScreenStatesSpec empty = UxScreenStatesSpec();

  /// Message affiché lorsqu'aucune donnée n'est disponible sur l'écran.
  final String emptyStateTitle;

  /// Appel à l'action proposé dans l'état vide (ex. `"Créer le premier client"`).
  final String emptyStateCta;

  /// Pattern de chargement visuel (`'skeleton'`, `'shimmer'`, `'spinner'`, `'inline'`).
  final String loadingPattern;

  /// Stratégie d'affichage et de reprise sur erreur réseau ou validation métier.
  final String errorHandling;

  /// Identifiants ou codes des règles `RG-xxx` plaçant l'écran ou ses champs en lecture seule.
  final List<String> readOnlyRuleIds;

  /// Vrai si au moins un état spécifique a été renseigné au-delà du défaut.
  bool get hasContent =>
      emptyStateTitle.trim().isNotEmpty ||
      emptyStateCta.trim().isNotEmpty ||
      (loadingPattern.trim().isNotEmpty && loadingPattern.trim() != 'skeleton') ||
      errorHandling.trim().isNotEmpty ||
      readOnlyRuleIds.isNotEmpty;

  /// Vérifie les invariants des états UX de l'écran.
  void validate() {
    for (final ruleId in readOnlyRuleIds) {
      if (ruleId.trim().isEmpty) {
        throw const FormatException(
          'UxScreenStatesSpec.readOnlyRuleIds ne peut pas contenir de référence vide.',
        );
      }
    }
  }

  /// Retourne une copie modifiée.
  UxScreenStatesSpec copyWith({
    String? emptyStateTitle,
    String? emptyStateCta,
    String? loadingPattern,
    String? errorHandling,
    List<String>? readOnlyRuleIds,
  }) => UxScreenStatesSpec(
    emptyStateTitle: emptyStateTitle ?? this.emptyStateTitle,
    emptyStateCta: emptyStateCta ?? this.emptyStateCta,
    loadingPattern: loadingPattern ?? this.loadingPattern,
    errorHandling: errorHandling ?? this.errorHandling,
    readOnlyRuleIds: readOnlyRuleIds ?? this.readOnlyRuleIds,
  );

  /// Sérialise les états UX en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'emptyStateTitle': emptyStateTitle,
    'emptyStateCta': emptyStateCta,
    'loadingPattern': loadingPattern,
    'errorHandling': errorHandling,
    'readOnlyRuleIds': readOnlyRuleIds,
  };

  /// Désérialise les états UX d'un écran depuis JSON.
  factory UxScreenStatesSpec.fromJson(Object? raw) {
    if (raw == null) return UxScreenStatesSpec.empty;
    if (raw is! Map) {
      throw const FormatException(
        'UxScreenStatesSpec doit être un objet JSON.',
      );
    }
    final rawLoading = (raw['loadingPattern'] as String?)?.trim() ?? '';
    final states = UxScreenStatesSpec(
      emptyStateTitle: (raw['emptyStateTitle'] as String?)?.trim() ?? '',
      emptyStateCta: (raw['emptyStateCta'] as String?)?.trim() ?? '',
      loadingPattern: rawLoading.isEmpty ? 'skeleton' : rawLoading,
      errorHandling: (raw['errorHandling'] as String?)?.trim() ?? '',
      readOnlyRuleIds: _stringList(raw['readOnlyRuleIds']),
    );
    states.validate();
    return states;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxScreenStatesSpec &&
          other.emptyStateTitle == emptyStateTitle &&
          other.emptyStateCta == emptyStateCta &&
          other.loadingPattern == loadingPattern &&
          other.errorHandling == errorHandling &&
          listEquals(other.readOnlyRuleIds, readOnlyRuleIds);

  @override
  int get hashCode => Object.hash(
    emptyStateTitle,
    emptyStateCta,
    loadingPattern,
    errorHandling,
    Object.hashAll(readOnlyRuleIds),
  );
}

/// Schéma directeur complet d'un écran applicatif (étape UX 3).
@immutable
class UxScreenSpec {
  /// Construit un schéma directeur d'écran immuable.
  UxScreenSpec({
    required this.id,
    this.code = 'SCR',
    required this.name,
    this.routeId = '',
    this.pattern = UxScreenPattern.masterDetail,
    this.purpose = '',
    List<String> personaIds = const <String>[],
    List<String> useCaseIds = const <String>[],
    List<String> requirementIds = const <String>[],
    this.primaryObjectId = '',
    List<UxScreenZoneSpec> zones = const <UxScreenZoneSpec>[],
    List<UxScreenAction> actions = const <UxScreenAction>[],
    UxScreenStatesSpec? states,
  }) : personaIds = List<String>.unmodifiable(personaIds),
       useCaseIds = List<String>.unmodifiable(useCaseIds),
       requirementIds = List<String>.unmodifiable(requirementIds),
       zones = List<UxScreenZoneSpec>.unmodifiable(zones),
       actions = List<UxScreenAction>.unmodifiable(actions),
       states = states ?? UxScreenStatesSpec.empty;

  /// Identifiant technique unique de l'écran (ex. `scr_commandes`).
  final String id;

  /// Code métier lisible de l'écran (ex. `SCR-001`).
  final String code;

  /// Nom fonctionnel de l'écran.
  final String name;

  /// Identifiant du `UxRouteNode` associé dans `UxNavigationSpec`.
  final String routeId;

  /// Pattern d'architecture spatiale retenu.
  final UxScreenPattern pattern;

  /// Rôle fonctionnel et intention utilisateur principale de l'écran.
  final String purpose;

  /// Identifiants des personas utilisant cet écran.
  final List<String> personaIds;

  /// Identifiants des cas d'usage réalisés sur cet écran.
  final List<String> useCaseIds;

  /// Identifiants ou codes des exigences fonctionnelles (`EXF-xxx`) couvertes.
  final List<String> requirementIds;

  /// Identifiant ou nom technique de l'objet métier principal affiché/édité.
  final String primaryObjectId;

  /// Configuration des zones spatiales (`SuperLayout`) de l'écran.
  final List<UxScreenZoneSpec> zones;

  /// Actions métier exposées sur l'écran.
  final List<UxScreenAction> actions;

  /// États vides, de chargement, d'erreur et de lecture seule.
  final UxScreenStatesSpec states;

  /// Recherche la configuration d'une zone cardinale donnée, ou `null` si absente.
  UxScreenZoneSpec? zoneFor(UxLayoutZoneName zone) {
    for (final item in zones) {
      if (item.zone == zone) return item;
    }
    return null;
  }

  /// Génère un jeu de zones initiales propres conforme à `SCREEN_DESIGN_AI_GUIDE.md` pour [pattern].
  static List<UxScreenZoneSpec> defaultZonesForPattern(
    UxScreenPattern pattern,
  ) => List<UxScreenZoneSpec>.unmodifiable(switch (pattern) {
    UxScreenPattern.masterDetail => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.west,
        sizePx: 320,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_master_search',
            title: 'Recherche & Filtres',
            kind: UxWidgetKind.searchFilterBar,
          ),
          UxZoneWidgetSlot(
            id: 'slot_master_list',
            title: 'Liste maître',
            kind: UxWidgetKind.masterList,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_detail_card',
            title: 'Fiche détail',
            kind: UxWidgetKind.detailCard,
          ),
        ],
      ),
    ],
    UxScreenPattern.dashboard => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.north,
        sizePx: 112,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_kpi_row',
            title: 'Indicateurs clés',
            kind: UxWidgetKind.kpiRow,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_main_chart',
            title: 'Graphique principal',
            kind: UxWidgetKind.chart,
          ),
          UxZoneWidgetSlot(
            id: 'slot_summary_table',
            title: 'Synthèse tabulaire',
            kind: UxWidgetKind.dataTable,
          ),
        ],
      ),
    ],
    UxScreenPattern.form => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        scrollable: true,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_form_main',
            title: 'Section principale',
            kind: UxWidgetKind.formSection,
          ),
        ],
      ),
    ],
    UxScreenPattern.tableExplorer => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.north,
        sizePx: 64,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_table_filters',
            title: 'Recherche & Filtres',
            kind: UxWidgetKind.searchFilterBar,
          ),
          UxZoneWidgetSlot(
            id: 'slot_table_toolbar',
            title: 'Barre d’outils',
            kind: UxWidgetKind.toolbar,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_data_table',
            title: 'Tableau principal',
            kind: UxWidgetKind.dataTable,
          ),
        ],
      ),
    ],
    UxScreenPattern.wizard => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.north,
        sizePx: 64,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_wizard_progress',
            title: 'Progression des étapes',
            kind: UxWidgetKind.statusBanner,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        scrollable: true,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_wizard_step',
            title: 'Étape courante',
            kind: UxWidgetKind.formSection,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.south,
        sizePx: 64,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_wizard_actions',
            title: 'Navigation d’assistant',
            kind: UxWidgetKind.toolbar,
          ),
        ],
      ),
    ],
    UxScreenPattern.kanban => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.north,
        sizePx: 60,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_kanban_filters',
            title: 'Recherche & Filtres',
            kind: UxWidgetKind.searchFilterBar,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_kanban_columns',
            title: 'Colonnes de flux',
            kind: UxWidgetKind.masterList,
          ),
        ],
      ),
    ],
    UxScreenPattern.documentA4 => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.north,
        sizePx: 88,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_doc_header',
            title: 'En-tête du document',
            kind: UxWidgetKind.detailCard,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_doc_body',
            title: 'Corps A4',
            kind: UxWidgetKind.dataTable,
          ),
        ],
      ),
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.south,
        sizePx: 56,
        axis: 'row',
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_doc_footer',
            title: 'Pied de page & totaux',
            kind: UxWidgetKind.detailCard,
          ),
        ],
      ),
    ],
    UxScreenPattern.custom => <UxScreenZoneSpec>[
      UxScreenZoneSpec(
        zone: UxLayoutZoneName.center,
        slots: <UxZoneWidgetSlot>[
          UxZoneWidgetSlot(
            id: 'slot_custom_main',
            title: 'Contenu principal',
            kind: UxWidgetKind.detailCard,
          ),
        ],
      ),
    ],
  });

  /// Vérifie les invariants de l'écran, de ses zones, actions et états UX.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('UxScreenSpec.id ne peut pas être vide.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('UxScreenSpec.name ne peut pas être vide.');
    }
    final seenZones = <UxLayoutZoneName>{};
    for (final zone in zones) {
      zone.validate();
      if (!seenZones.add(zone.zone)) {
        throw FormatException(
          'Zone UX dupliquée « ${zone.zone.name} » sur l’écran « $name ».',
        );
      }
    }
    final seenActionIds = <String>{};
    for (final action in actions) {
      action.validate();
      if (!seenActionIds.add(action.id)) {
        throw FormatException(
          'Action UX dupliquée « ${action.id} » sur l’écran « $name ».',
        );
      }
    }
    states.validate();
  }

  /// Retourne une copie modifiée.
  UxScreenSpec copyWith({
    String? id,
    String? code,
    String? name,
    String? routeId,
    UxScreenPattern? pattern,
    String? purpose,
    List<String>? personaIds,
    List<String>? useCaseIds,
    List<String>? requirementIds,
    String? primaryObjectId,
    List<UxScreenZoneSpec>? zones,
    List<UxScreenAction>? actions,
    UxScreenStatesSpec? states,
  }) => UxScreenSpec(
    id: id ?? this.id,
    code: code ?? this.code,
    name: name ?? this.name,
    routeId: routeId ?? this.routeId,
    pattern: pattern ?? this.pattern,
    purpose: purpose ?? this.purpose,
    personaIds: personaIds ?? this.personaIds,
    useCaseIds: useCaseIds ?? this.useCaseIds,
    requirementIds: requirementIds ?? this.requirementIds,
    primaryObjectId: primaryObjectId ?? this.primaryObjectId,
    zones: zones ?? this.zones,
    actions: actions ?? this.actions,
    states: states ?? this.states,
  );

  /// Sérialise le schéma directeur d'écran en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'routeId': routeId,
    'pattern': pattern.name,
    'purpose': purpose,
    'personaIds': personaIds,
    'useCaseIds': useCaseIds,
    'requirementIds': requirementIds,
    'primaryObjectId': primaryObjectId,
    'zones': [for (final z in zones) z.toJson()],
    'actions': [for (final a in actions) a.toJson()],
    'states': states.toJson(),
  };

  /// Désérialise un schéma directeur d'écran depuis JSON avec valeurs de repli tolérantes.
  factory UxScreenSpec.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('UxScreenSpec doit être un objet JSON.');
    }
    final rawName =
        (raw['name'] as String?)?.trim() ??
        (raw['title'] as String?)?.trim() ??
        '';
    final name = rawName.isEmpty ? 'Écran sans nom' : rawName;
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawCode = (raw['code'] as String?)?.trim() ?? '';

    final zonesByKind = <UxLayoutZoneName, UxScreenZoneSpec>{};
    if (raw['zones'] is List) {
      for (final item in raw['zones'] as List) {
        final parsed = UxScreenZoneSpec.fromJson(item);
        final existing = zonesByKind[parsed.zone];
        if (existing == null) {
          zonesByKind[parsed.zone] = parsed;
        } else {
          final mergedSlots = <UxZoneWidgetSlot>[...existing.slots];
          final seenIds = <String>{for (final s in mergedSlots) s.id};
          for (final slot in parsed.slots) {
            var candidate = slot;
            if (!seenIds.add(candidate.id)) {
              var suffix = 2;
              while (!seenIds.add('${candidate.id}_$suffix')) {
                suffix++;
              }
              candidate = candidate.copyWith(id: '${candidate.id}_$suffix');
            }
            mergedSlots.add(candidate);
          }
          zonesByKind[parsed.zone] = existing.copyWith(slots: mergedSlots);
        }
      }
    }

    final parsedActions = <UxScreenAction>[];
    final seenActionIds = <String>{};
    if (raw['actions'] is List) {
      for (final item in raw['actions'] as List) {
        var action = UxScreenAction.fromJson(item);
        if (!seenActionIds.add(action.id)) {
          var suffix = 2;
          while (!seenActionIds.add('${action.id}_$suffix')) {
            suffix++;
          }
          action = action.copyWith(id: '${action.id}_$suffix');
        }
        parsedActions.add(action);
      }
    }

    final screen = UxScreenSpec(
      id: rawId.isEmpty ? 'scr_${name.hashCode.abs()}' : rawId,
      code: rawCode.isEmpty ? 'SCR' : rawCode,
      name: name,
      routeId: (raw['routeId'] as String?)?.trim() ?? '',
      pattern: UxScreenPattern.fromJson(raw['pattern']),
      purpose: (raw['purpose'] as String?)?.trim() ?? '',
      personaIds: _stringList(raw['personaIds']),
      useCaseIds: _stringList(raw['useCaseIds']),
      requirementIds: _stringList(raw['requirementIds']),
      primaryObjectId: (raw['primaryObjectId'] as String?)?.trim() ?? '',
      zones: zonesByKind.values.toList(),
      actions: parsedActions,
      states: UxScreenStatesSpec.fromJson(raw['states']),
    );
    screen.validate();
    return screen;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxScreenSpec &&
          other.id == id &&
          other.code == code &&
          other.name == name &&
          other.routeId == routeId &&
          other.pattern == pattern &&
          other.purpose == purpose &&
          listEquals(other.personaIds, personaIds) &&
          listEquals(other.useCaseIds, useCaseIds) &&
          listEquals(other.requirementIds, requirementIds) &&
          other.primaryObjectId == primaryObjectId &&
          listEquals(other.zones, zones) &&
          listEquals(other.actions, actions) &&
          other.states == states;

  @override
  int get hashCode => Object.hash(
    id,
    code,
    name,
    routeId,
    pattern,
    purpose,
    Object.hashAll(personaIds),
    Object.hashAll(useCaseIds),
    Object.hashAll(requirementIds),
    primaryObjectId,
    Object.hashAll(zones),
    Object.hashAll(actions),
    states,
  );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return [
    for (final item in raw)
      if (item is String && item.trim().isNotEmpty) item.trim(),
  ];
}
