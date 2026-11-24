/// Modèles immuables de projection des items de design porteurs des indicateurs
/// d'avancement ([ContractStage] / [ContractStatus]) pour l'onglet Build,
/// agrégés par domaine fonctionnel ([BuildDomainDesignItems]).
library;

import 'package:flutter/foundation.dart';

import 'domain_catalog.dart';
import 'domain_contracts.dart';
import 'usecase_orchestration_spec.dart';

/// Catégorie d'élément de conception suivi dans l'espace Build.
enum BuildDesignItemKind {
  /// Entrée issue du catalogue `Modèles & Contrats` ([DomainContracts]).
  model(sectionTitle: 'Modèles & Contrats', shortLabel: 'Modèle'),

  /// Cas d'usage applicatif CQRS ([ApplicationUseCaseSpec]).
  useCase(sectionTitle: 'Cas d’usage', shortLabel: 'Use Case'),

  /// Saga orchestrée ou chorégraphiée ([OrchestrationSagaSpec]).
  saga(sectionTitle: 'Sagas', shortLabel: 'Saga');

  const BuildDesignItemKind({
    required this.sectionTitle,
    required this.shortLabel,
  });

  /// Titre de la section repliable dans la vue Build.
  final String sectionTitle;

  /// Libellé court utilisé dans les filtres et infobulles.
  final String shortLabel;
}

/// Élément de conception d'un domaine muni des 4 indicateurs d'avancement
/// (`Conception`, `Validation`, `Code`, `Livraison`).
@immutable
class BuildDesignItem {
  /// Crée un item de suivi Build.
  BuildDesignItem({
    required this.domainId,
    required this.id,
    required this.kind,
    required this.name,
    this.subtitle = '',
    this.version = '0.0.1',
    this.primaryBadge = '',
    this.secondaryBadge = '',
    this.groupName = '',
    Map<ContractStage, ContractStatus> states =
        const <ContractStage, ContractStatus>{},
  }) : states = Map<ContractStage, ContractStatus>.unmodifiable(states);

  /// Identifiant du domaine fonctionnel propriétaire.
  final String domainId;

  /// Identifiant stable de l'entrée dans son référentiel d'origine.
  final String id;

  /// Catégorie de l'item (`model`, `useCase`, `saga`).
  final BuildDesignItemKind kind;

  /// Nom principal (nom DSL du contrat, nom technique du Use Case ou de la Saga).
  final String name;

  /// Titre fonctionnel optionnel affiché sous [name] lorsqu'il en diffère.
  final String subtitle;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// Badge principal (type DSL `model`/`dto`…, ou code `UC-xxx` / `SAGA-xxx`).
  final String primaryBadge;

  /// Badge secondaire (version `v0.0.1`, qualification `Command`/`Query` ou mode de coordination).
  final String secondaryBadge;

  /// Rubrique ou contexte de rattachement (rubrique DSL ou Bounded Context).
  final String groupName;

  /// États d'avancement par étape.
  final Map<ContractStage, ContractStatus> states;

  /// Retourne le statut de [stage] ([ContractStatus.pending] par défaut).
  ContractStatus statusOf(ContractStage stage) =>
      states[stage] ?? ContractStatus.pending;

  /// Nombre d'étapes terminées ([ContractStatus.done]).
  int get doneStagesCount => ContractStage.values
      .where((stage) => statusOf(stage) == ContractStatus.done)
      .length;

  /// Nombre d'étapes en cours ([ContractStatus.inProgress]).
  int get inProgressStagesCount => ContractStage.values
      .where((stage) => statusOf(stage) == ContractStatus.inProgress)
      .length;

  /// Vérifie les invariants de l'item.
  void validate() {
    if (domainId.trim().isEmpty) {
      throw const FormatException('BuildDesignItem.domainId requis.');
    }
    if (id.trim().isEmpty) {
      throw const FormatException('BuildDesignItem.id requis.');
    }
    if (name.trim().isEmpty) {
      throw const FormatException('BuildDesignItem.name requis.');
    }
  }

  /// Indique si l'item correspond à la recherche libre [rawQuery].
  bool matchesQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q) ||
        version.toLowerCase().contains(q) ||
        primaryBadge.toLowerCase().contains(q) ||
        secondaryBadge.toLowerCase().contains(q) ||
        groupName.toLowerCase().contains(q) ||
        kind.sectionTitle.toLowerCase().contains(q) ||
        kind.shortLabel.toLowerCase().contains(q);
  }

  /// Indique si l'item satisfait le filtre combiné [stage] / [status].
  ///
  /// - Si [stage] et [status] sont fournis : l'étape [stage] doit valoir [status].
  /// - Si seul [status] est fourni : au moins une étape doit valoir [status].
  /// - Si seul [stage] est fourni : l'étape [stage] doit être démarrée ou terminée
  ///   (différente de [ContractStatus.pending]).
  bool matchesStageFilter({ContractStage? stage, ContractStatus? status}) {
    if (stage == null && status == null) return true;
    if (stage != null && status != null) {
      return statusOf(stage) == status;
    }
    if (status != null) {
      return ContractStage.values.any((s) => statusOf(s) == status);
    }
    return statusOf(stage!) != ContractStatus.pending;
  }

  /// Copie modifiée.
  BuildDesignItem copyWith({
    String? domainId,
    String? id,
    BuildDesignItemKind? kind,
    String? name,
    String? subtitle,
    String? version,
    String? primaryBadge,
    String? secondaryBadge,
    String? groupName,
    Map<ContractStage, ContractStatus>? states,
  }) => BuildDesignItem(
    domainId: domainId ?? this.domainId,
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    subtitle: subtitle ?? this.subtitle,
    version: version ?? this.version,
    primaryBadge: primaryBadge ?? this.primaryBadge,
    secondaryBadge: secondaryBadge ?? this.secondaryBadge,
    groupName: groupName ?? this.groupName,
    states: states ?? this.states,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildDesignItem &&
          other.domainId == domainId &&
          other.id == id &&
          other.kind == kind &&
          other.name == name &&
          other.subtitle == subtitle &&
          other.version == version &&
          other.primaryBadge == primaryBadge &&
          other.secondaryBadge == secondaryBadge &&
          other.groupName == groupName &&
          mapEquals(other.states, states);

  @override
  int get hashCode => Object.hash(
    domainId,
    id,
    kind,
    name,
    subtitle,
    version,
    primaryBadge,
    secondaryBadge,
    groupName,
    Object.hashAllUnordered([
      for (final e in states.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// Vue agrégée immuable des items de design d'un [FunctionalDomain].
@immutable
class BuildDomainDesignItems {
  /// Crée la projection Build d'un domaine.
  BuildDomainDesignItems({
    required this.domainId,
    required this.domainName,
    required this.domainCode,
    List<BuildDesignItem> models = const <BuildDesignItem>[],
    List<BuildDesignItem> useCases = const <BuildDesignItem>[],
    List<BuildDesignItem> sagas = const <BuildDesignItem>[],
  }) : models = List<BuildDesignItem>.unmodifiable(models),
       useCases = List<BuildDesignItem>.unmodifiable(useCases),
       sagas = List<BuildDesignItem>.unmodifiable(sagas);

  /// Extrait tous les modèles/contrats, cas d'usage et sagas de [domain].
  factory BuildDomainDesignItems.fromDomain(FunctionalDomain domain) {
    final contracts = domain.contracts;
    final models = <BuildDesignItem>[];
    if (contracts != null) {
      for (final group in contracts.groups) {
        for (final node in group.children) {
          final detail = contracts.details[node.id] ?? ContractDetails.defaults;
          final trimmedTitle = detail.title.trim();
          models.add(
            BuildDesignItem(
              domainId: domain.id,
              id: node.id,
              kind: BuildDesignItemKind.model,
              name: node.name,
              subtitle: trimmedTitle == node.name ? '' : trimmedTitle,
              version: detail.version,
              primaryBadge: node.type,
              secondaryBadge: 'v${detail.version}',
              groupName: group.name,
              states: detail.states,
            ),
          );
        }
      }
    }

    final orchestration = domain.useCaseOrchestration;
    final useCases = <BuildDesignItem>[
      if (orchestration != null)
        for (final uc in orchestration.useCases)
          BuildDesignItem(
            domainId: domain.id,
            id: uc.id,
            kind: BuildDesignItemKind.useCase,
            name: uc.name.trim().isNotEmpty ? uc.name.trim() : uc.title.trim(),
            subtitle:
                uc.title.trim().isNotEmpty && uc.title.trim() != uc.name.trim()
                ? uc.title.trim()
                : '',
            version: uc.version,
            primaryBadge: uc.code,
            secondaryBadge: '${uc.cqrsType.label} · v${uc.version}',
            groupName: uc.boundedContext,
            states: uc.states,
          ),
    ];

    final sagas = <BuildDesignItem>[
      if (orchestration != null)
        for (final saga in orchestration.sagas)
          BuildDesignItem(
            domainId: domain.id,
            id: saga.id,
            kind: BuildDesignItemKind.saga,
            name: saga.name.trim().isNotEmpty
                ? saga.name.trim()
                : saga.title.trim(),
            subtitle:
                saga.title.trim().isNotEmpty &&
                    saga.title.trim() != saga.name.trim()
                ? saga.title.trim()
                : '',
            version: saga.version,
            primaryBadge: saga.code,
            secondaryBadge: '${saga.coordinationMode.label} · v${saga.version}',
            groupName: saga.boundedContexts.join(', '),
            states: saga.states,
          ),
    ];

    return BuildDomainDesignItems(
      domainId: domain.id,
      domainName: domain.name,
      domainCode: domain.domainCode,
      models: models,
      useCases: useCases,
      sagas: sagas,
    );
  }

  /// Identifiant du domaine.
  final String domainId;

  /// Nom affiché du domaine.
  final String domainName;

  /// Code canonique du domaine.
  final String domainCode;

  /// Entrées issues de `Modèles & Contrats`.
  final List<BuildDesignItem> models;

  /// Entrées issues des Use Cases applicatifs.
  final List<BuildDesignItem> useCases;

  /// Entrées issues des Sagas d'orchestration / chorégraphie.
  final List<BuildDesignItem> sagas;

  /// Nombre total d'éléments de conception dans ce domaine.
  int get totalCount => models.length + useCases.length + sagas.length;

  /// Indique si le domaine ne contient encore aucun élément de conception.
  bool get isEmpty => totalCount == 0;

  /// Tous les items du domaine, toutes catégories confondues.
  Iterable<BuildDesignItem> get allItems sync* {
    yield* models;
    yield* useCases;
    yield* sagas;
  }

  /// Items de la catégorie [kind] sans filtrage.
  List<BuildDesignItem> itemsOf(BuildDesignItemKind kind) => switch (kind) {
    BuildDesignItemKind.model => models,
    BuildDesignItemKind.useCase => useCases,
    BuildDesignItemKind.saga => sagas,
  };

  /// Retourne les items de [kind] filtrés par recherche, catégorie et avancement.
  List<BuildDesignItem> filterItems(
    BuildDesignItemKind kind, {
    String query = '',
    BuildDesignItemKind? kindFilter,
    ContractStage? stageFilter,
    ContractStatus? statusFilter,
  }) {
    if (kindFilter != null && kindFilter != kind) {
      return const <BuildDesignItem>[];
    }
    final source = itemsOf(kind);
    if (query.trim().isEmpty && stageFilter == null && statusFilter == null) {
      return source;
    }
    return [
      for (final item in source)
        if (item.matchesQuery(query) &&
            item.matchesStageFilter(stage: stageFilter, status: statusFilter))
          item,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildDomainDesignItems &&
          other.domainId == domainId &&
          other.domainName == domainName &&
          other.domainCode == domainCode &&
          listEquals(other.models, models) &&
          listEquals(other.useCases, useCases) &&
          listEquals(other.sagas, sagas);

  @override
  int get hashCode => Object.hash(
    domainId,
    domainName,
    domainCode,
    Object.hashAll(models),
    Object.hashAll(useCases),
    Object.hashAll(sagas),
  );
}
