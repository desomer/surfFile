/// Modèles immuables de projection des items de design porteurs des indicateurs
/// d'avancement ([ContractStage] / [ContractStatus]) et des métadonnées
/// d'évolution inter-itérations (`badge_only`) pour l'onglet Build, agrégés par
/// domaine fonctionnel ([BuildDomainDesignItems]).
library;

import 'package:flutter/foundation.dart';

import '../services/design_evolution_analyzer.dart';
import 'domain_catalog.dart';
import 'domain_contracts.dart';
import 'domain_iteration_snapshot.dart';
import 'usecase_orchestration_spec.dart';
import 'value_object_spec.dart';

/// Catégorie d'élément de conception suivi dans l'espace Build.
enum BuildDesignItemKind {
  /// Value Object atomique ou composite ([ValueObjectSpec], Domaine ou Shared Kernel).
  valueObject(sectionTitle: 'Value Objects', shortLabel: 'Value Object'),

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
/// (`Conception`, `Validation`, `Code`, `Livraison`) et d'un rapport optionnel
/// d'évolution vis-à-vis du jalon actif (politique non-intrusive `badge_only`).
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
    this.valueObjectScope,
    this.evolution,
  }) : states = Map<ContractStage, ContractStatus>.unmodifiable(states);

  /// Identifiant du domaine fonctionnel propriétaire.
  final String domainId;

  /// Identifiant stable de l'entrée dans son référentiel d'origine.
  final String id;

  /// Catégorie de l'item (`valueObject`, `model`, `useCase`, `saga`).
  final BuildDesignItemKind kind;

  /// Nom principal (nom technique du VO, nom DSL du contrat, nom du Use Case ou de la Saga).
  final String name;

  /// Titre fonctionnel optionnel affiché sous [name] lorsqu'il en diffère.
  final String subtitle;

  /// Version sémantique (`x.y.z`).
  final String version;

  /// Badge principal (`composite` / type primitif, type DSL `model`/`dto`…, ou code `UC-xxx` / `SAGA-xxx`).
  final String primaryBadge;

  /// Badge secondaire (version `v0.0.1`, `Shared Kernel`, qualification `Command`/`Query` ou coordination).
  final String secondaryBadge;

  /// Rubrique ou contexte de rattachement (catégorie VO, rubrique DSL ou Bounded Context).
  final String groupName;

  /// États d'avancement par étape, reflétant strictement les états persistés
  /// sans rétrogradation automatique en cas d'évolution (`badge_only`).
  final Map<ContractStage, ContractStatus> states;

  /// Portée d'origine lorsque [kind] vaut [BuildDesignItemKind.valueObject] (`domain` ou `shared`).
  final ValueObjectScope? valueObjectScope;

  /// Rapport d'évolution et d'impact vis-à-vis du jalon d'itération actif.
  final ArtifactEvolutionReport? evolution;

  /// État d'évolution de l'item par rapport au jalon actif ([ArtifactEvolutionState.noBaseline] par défaut).
  ArtifactEvolutionState get evolutionState =>
      evolution?.state ?? ArtifactEvolutionState.noBaseline;

  /// Indique si l'item requiert une attention d'implémentation suite à évolution (`added`, `modified` ou `impacted`).
  bool get isEvolved => evolutionState.isActionable;

  /// Version sémantique capturée dans le jalon de référence (`null` si nouveau ou sans jalon).
  String? get baselineVersion => evolution?.baselineVersion;

  /// Niveau d'incrément SemVer effectif détecté depuis le jalon ([SemVerBump.none] par défaut).
  SemVerBump get effectiveBump => evolution?.effectiveBump ?? SemVerBump.none;

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
        kind.shortLabel.toLowerCase().contains(q) ||
        (valueObjectScope?.label.toLowerCase().contains(q) ?? false);
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

  /// Indique si l'item satisfait le filtre d'évolution [filter] ou [actionableOnly].
  bool matchesEvolutionFilter(
    ArtifactEvolutionState? filter, {
    bool actionableOnly = false,
  }) {
    if (actionableOnly) {
      return evolutionState.isActionable;
    }
    if (filter != null) {
      return evolutionState == filter;
    }
    return true;
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
    ValueObjectScope? valueObjectScope,
    bool clearValueObjectScope = false,
    ArtifactEvolutionReport? evolution,
    bool clearEvolution = false,
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
    valueObjectScope: clearValueObjectScope
        ? null
        : (valueObjectScope ?? this.valueObjectScope),
    evolution: clearEvolution ? null : (evolution ?? this.evolution),
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
          other.valueObjectScope == valueObjectScope &&
          other.evolution == evolution &&
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
    valueObjectScope,
    evolution,
    Object.hashAllUnordered([
      for (final e in states.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// Vue agrégée immuable des items de design d'un [FunctionalDomain] enrichie
/// des Value Objects visibles et de l'analyse d'évolution vis-à-vis du jalon actif.
@immutable
class BuildDomainDesignItems {
  /// Crée la projection Build d'un domaine.
  BuildDomainDesignItems({
    required this.domainId,
    required this.domainName,
    required this.domainCode,
    List<BuildDesignItem> valueObjects = const <BuildDesignItem>[],
    List<BuildDesignItem> models = const <BuildDesignItem>[],
    List<BuildDesignItem> useCases = const <BuildDesignItem>[],
    List<BuildDesignItem> sagas = const <BuildDesignItem>[],
    this.baselineSnapshot,
    List<ArtifactEvolutionReport> removedArtifacts =
        const <ArtifactEvolutionReport>[],
  }) : valueObjects = List<BuildDesignItem>.unmodifiable(valueObjects),
       models = List<BuildDesignItem>.unmodifiable(models),
       useCases = List<BuildDesignItem>.unmodifiable(useCases),
       sagas = List<BuildDesignItem>.unmodifiable(sagas),
       removedArtifacts = List<ArtifactEvolutionReport>.unmodifiable(
         removedArtifacts,
       );

  /// Extrait tous les Value Objects (Domaine + Shared Kernel non masqués),
  /// modèles/contrats, cas d'usage et sagas de [domain], en y attachant les
  /// rapports d'évolution sans jamais altérer les états d'avancement (`badge_only`).
  factory BuildDomainDesignItems.fromDomain(
    FunctionalDomain domain, {
    DomainCatalog? catalog,
    DomainIterationSnapshot? baselineOverride,
    DomainEvolutionReport? evolutionReport,
  }) {
    final effectiveEvolution =
        evolutionReport ??
        DesignEvolutionAnalyzer.analyzeDomain(
          domain: domain,
          catalog: catalog,
          baselineOverride: baselineOverride,
        );

    final resolvedVos = _resolveVisibleValueObjects(domain, catalog);
    final valueObjects = <BuildDesignItem>[
      for (final resolved in resolvedVos)
        () {
          final vo = resolved.spec;
          final scope = resolved.scope;
          final trimmedLabel = vo.name.trim();
          final category = vo.category.trim().isEmpty
              ? 'Domaine'
              : vo.category.trim();
          return BuildDesignItem(
            domainId: domain.id,
            id: vo.id,
            kind: BuildDesignItemKind.valueObject,
            name: vo.technicalName,
            subtitle: trimmedLabel.isNotEmpty && trimmedLabel != vo.technicalName
                ? trimmedLabel
                : '',
            version: vo.version,
            primaryBadge: vo.isComposite
                ? 'composite'
                : vo.primitiveType.dslKeyword,
            secondaryBadge: scope == ValueObjectScope.shared
                ? 'Shared Kernel · v${vo.version}'
                : 'v${vo.version}',
            groupName: scope == ValueObjectScope.shared
                ? 'Shared Kernel · $category'
                : category,
            states: vo.states,
            valueObjectScope: scope,
            evolution: effectiveEvolution.valueObjects[vo.id],
          );
        }(),
    ];

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
              evolution: effectiveEvolution.models[node.id],
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
            evolution: effectiveEvolution.useCases[uc.id],
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
            evolution: effectiveEvolution.sagas[saga.id],
          ),
    ];

    return BuildDomainDesignItems(
      domainId: domain.id,
      domainName: domain.name,
      domainCode: domain.domainCode,
      valueObjects: valueObjects,
      models: models,
      useCases: useCases,
      sagas: sagas,
      baselineSnapshot: effectiveEvolution.baseline,
      removedArtifacts: effectiveEvolution.removedArtifacts,
    );
  }

  static List<ResolvedValueObject> _resolveVisibleValueObjects(
    FunctionalDomain domain,
    DomainCatalog? catalog,
  ) {
    final resolved = <ResolvedValueObject>[];
    final seenTechNames = <String>{};
    for (final vo in domain.valueObjects) {
      seenTechNames.add(vo.technicalName.toLowerCase());
      resolved.add(
        ResolvedValueObject(
          spec: vo,
          scope: ValueObjectScope.domain,
          domainId: domain.id,
        ),
      );
    }
    if (catalog != null) {
      for (final vo in catalog.sharedValueObjects) {
        if (seenTechNames.add(vo.technicalName.toLowerCase())) {
          resolved.add(
            ResolvedValueObject(spec: vo, scope: ValueObjectScope.shared),
          );
        }
      }
    }
    return resolved;
  }

  /// Identifiant du domaine.
  final String domainId;

  /// Nom affiché du domaine.
  final String domainName;

  /// Code canonique du domaine.
  final String domainCode;

  /// Value Objects visibles du domaine (Domaine + Shared Kernel non masqués).
  final List<BuildDesignItem> valueObjects;

  /// Entrées issues de `Modèles & Contrats`.
  final List<BuildDesignItem> models;

  /// Entrées issues des Use Cases applicatifs.
  final List<BuildDesignItem> useCases;

  /// Entrées issues des Sagas d'orchestration / chorégraphie.
  final List<BuildDesignItem> sagas;

  /// Jalon d'itération actif servant de baseline de comparaison (`null` si aucun).
  final DomainIterationSnapshot? baselineSnapshot;

  /// Artefacts présents dans [baselineSnapshot] mais supprimés dans l'état courant.
  final List<ArtifactEvolutionReport> removedArtifacts;

  /// Indique si un jalon de baseline est actif pour cette projection.
  bool get hasBaseline => baselineSnapshot != null;

  /// Nombre d'éléments nécessitant une action suite à évolution (`added`, `modified`, `impacted`).
  int get actionableCount => allItems.where((item) => item.isEvolved).length;

  /// Nombre total d'éléments de conception dans ce domaine.
  int get totalCount =>
      valueObjects.length + models.length + useCases.length + sagas.length;

  /// Indique si le domaine ne contient encore aucun élément de conception.
  bool get isEmpty => totalCount == 0;

  /// Tous les items du domaine, toutes catégories confondues.
  Iterable<BuildDesignItem> get allItems sync* {
    yield* valueObjects;
    yield* models;
    yield* useCases;
    yield* sagas;
  }

  /// Items de la catégorie [kind] sans filtrage.
  List<BuildDesignItem> itemsOf(BuildDesignItemKind kind) => switch (kind) {
    BuildDesignItemKind.valueObject => valueObjects,
    BuildDesignItemKind.model => models,
    BuildDesignItemKind.useCase => useCases,
    BuildDesignItemKind.saga => sagas,
  };

  /// Retourne les items de [kind] filtrés par recherche, catégorie, avancement et évolution.
  List<BuildDesignItem> filterItems(
    BuildDesignItemKind kind, {
    String query = '',
    BuildDesignItemKind? kindFilter,
    ContractStage? stageFilter,
    ContractStatus? statusFilter,
    ArtifactEvolutionState? evolutionFilter,
    bool actionableOnly = false,
  }) {
    if (kindFilter != null && kindFilter != kind) {
      return const <BuildDesignItem>[];
    }
    final source = itemsOf(kind);
    if (query.trim().isEmpty &&
        stageFilter == null &&
        statusFilter == null &&
        evolutionFilter == null &&
        !actionableOnly) {
      return source;
    }
    return [
      for (final item in source)
        if (item.matchesQuery(query) &&
            item.matchesStageFilter(stage: stageFilter, status: statusFilter) &&
            item.matchesEvolutionFilter(
              evolutionFilter,
              actionableOnly: actionableOnly,
            ))
          item,
    ];
  }

  /// Alias de [filterItems] filtrant les items de [kind] selon la recherche,
  /// l'avancement et l'état d'évolution inter-itérations.
  List<BuildDesignItem> filteredItemsOf(
    BuildDesignItemKind kind, {
    String query = '',
    BuildDesignItemKind? kindFilter,
    ContractStage? stageFilter,
    ContractStatus? statusFilter,
    ArtifactEvolutionState? evolutionFilter,
    bool actionableOnly = false,
  }) => filterItems(
    kind,
    query: query,
    kindFilter: kindFilter,
    stageFilter: stageFilter,
    statusFilter: statusFilter,
    evolutionFilter: evolutionFilter,
    actionableOnly: actionableOnly,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildDomainDesignItems &&
          other.domainId == domainId &&
          other.domainName == domainName &&
          other.domainCode == domainCode &&
          other.baselineSnapshot == baselineSnapshot &&
          listEquals(other.valueObjects, valueObjects) &&
          listEquals(other.models, models) &&
          listEquals(other.useCases, useCases) &&
          listEquals(other.sagas, sagas) &&
          listEquals(other.removedArtifacts, removedArtifacts);

  @override
  int get hashCode => Object.hash(
    domainId,
    domainName,
    domainCode,
    baselineSnapshot,
    Object.hashAll(valueObjects),
    Object.hashAll(models),
    Object.hashAll(useCases),
    Object.hashAll(sagas),
    Object.hashAll(removedArtifacts),
  );
}
