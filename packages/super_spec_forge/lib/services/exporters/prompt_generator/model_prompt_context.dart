/// Contexte résolu d'un modèle/contrat ([ModelPromptContext]) partagé entre
/// les prompts d'implémentation, de tests unitaires et de persistance.
library;

import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../../models/build_design_item.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/business_object_spec.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/domain_contracts.dart';
import '../../../models/domain_layer_spec.dart';
import '../../../models/spec_forge_project.dart';
import '../../../models/value_object_spec.dart';

/// Regroupe les métadonnées métier et hexagonales résolues pour un item modèle.
class ModelPromptContext {
  const ModelPromptContext._({
    required this.domain,
    required this.item,
    required this.node,
    required this.detail,
    required this.objectSpec,
    required this.layerSpec,
    required this.refTargets,
    required this.resolutionProject,
    required this.dslType,
    required this.groupName,
    required this.portName,
    required this.availableValueObjects,
    required this.referencedValueObjects,
  });

  /// Domaine propriétaire.
  final FunctionalDomain domain;

  /// Élément Build sélectionné.
  final BuildDesignItem item;

  /// Nœud DSL correspondant, s'il existe.
  final JsonNode? node;

  /// Détails (titre, version, états) du contrat.
  final ContractDetails detail;

  /// Spécification de l'objet métier associé.
  final BusinessObjectSpec objectSpec;

  /// Spécification de la couche Domain (Architecture Hexagonale).
  final HexagonalDomainLayerSpec layerSpec;

  /// Cibles de référence techniques indexées par ID d'entrée.
  final Map<String, String> refTargets;

  /// Projet synthétique permettant la résolution des références et préférences JSON Schema.
  final SpecForgeProject resolutionProject;

  /// Type DSL effectif (`model`, `component`, `createxdto`, etc.).
  final String dslType;

  /// Rubrique DSL parente.
  final String groupName;

  /// Nom du port sortant Repository.
  final String portName;

  /// Tous les Value Objects visibles dans ce domaine (Domaine + Shared Kernel).
  final List<ResolvedValueObject> availableValueObjects;

  /// Value Objects effectivement référencés par [objectSpec] (y compris
  /// récursivement par les champs des Value Objects composites).
  final List<ResolvedValueObject> referencedValueObjects;

  /// Extrait et résout le contexte complet de [item] dans [domain].
  factory ModelPromptContext.resolve({
    required FunctionalDomain domain,
    required BuildDesignItem item,
    DomainCatalog? catalog,
    BusinessObjectModelPreferences? modelPreferences,
  }) {
    final contracts = domain.contracts;
    final node = contracts?.entryById(item.id);
    final detail =
        (node != null ? contracts?.details[node.id] : null) ??
        ContractDetails(title: item.subtitle, version: item.version);
    final objectSpec = node != null && contracts != null
        ? contracts.objectFor(node)
        : BusinessObjectSpec(
            id: item.id,
            name: item.subtitle.isNotEmpty ? item.subtitle : item.name,
            technicalName: item.name,
          );
    final layerSpec = node != null && contracts != null
        ? contracts.domainLayerFor(node)
        : HexagonalDomainLayerSpec.empty;
    final refTargets = node != null && contracts != null
        ? contracts.referenceTargetsOf(node)
        : const <String, String>{};
    final relatedObjects = <BusinessObjectSpec>[
      if (contracts != null)
        for (final entry in refTargets.entries)
          if (contracts.entryById(entry.key) case final otherNode?)
            contracts
                .objectFor(otherNode)
                .copyWith(technicalName: entry.value),
    ];
    final now = DateTime.now().toUtc();
    final resolutionProject = SpecForgeProject(
      id: 'prompt_ctx_${domain.id}_${item.id}',
      name: domain.name,
      initialIdea: domain.description.trim().isNotEmpty
          ? domain.description.trim()
          : domain.name,
      createdAt: now,
      updatedAt: now,
      businessObjects: <BusinessObjectSpec>[objectSpec, ...relatedObjects],
      businessObjectModelPreferences:
          modelPreferences ?? BusinessObjectModelPreferences.defaults,
    );
    final dslType =
        node?.type ?? (item.primaryBadge.isEmpty ? 'model' : item.primaryBadge);
    final groupName = node?.parent?.name ?? item.groupName;
    final rawPort = layerSpec.persistencePolicy.repositoryPortName.trim();
    final portName = rawPort.isNotEmpty
        ? rawPort
        : '${objectSpec.technicalName}Repository';

    final availableValueObjects = catalog != null
        ? catalog.resolvedValueObjectsForDomain(domain.id)
        : List<ResolvedValueObject>.unmodifiable(<ResolvedValueObject>[
            for (final vo in domain.valueObjects)
              ResolvedValueObject(
                spec: vo,
                scope: ValueObjectScope.domain,
                domainId: domain.id,
              ),
          ]);
    final referencedValueObjects = _collectReferencedValueObjects(
      objectSpec,
      availableValueObjects,
    );

    return ModelPromptContext._(
      domain: domain,
      item: item,
      node: node,
      detail: detail,
      objectSpec: objectSpec,
      layerSpec: layerSpec,
      refTargets: refTargets,
      resolutionProject: resolutionProject,
      dslType: dslType,
      groupName: groupName,
      portName: portName,
      availableValueObjects: availableValueObjects,
      referencedValueObjects: referencedValueObjects,
    );
  }

  static List<ResolvedValueObject> _collectReferencedValueObjects(
    BusinessObjectSpec objectSpec,
    List<ResolvedValueObject> pool,
  ) {
    if (pool.isEmpty) return const <ResolvedValueObject>[];
    final byId = <String, ResolvedValueObject>{
      for (final item in pool) item.spec.id: item,
    };
    final byTech = <String, ResolvedValueObject>{
      for (final item in pool) item.spec.technicalName.toLowerCase(): item,
    };
    final collected = <ResolvedValueObject>[];
    final seenIds = <String>{};

    ResolvedValueObject? lookup(String ref) {
      final clean = ref.trim();
      if (clean.isEmpty) return null;
      return byId[clean] ?? byTech[clean.toLowerCase()];
    }

    void collectAttributes(List<BusinessAttribute> attrs) {
      for (final attr in attrs) {
        if (attr.type == BusinessAttributeType.valueObject) {
          final resolved = lookup(attr.valueObjectId);
          if (resolved != null && seenIds.add(resolved.spec.id)) {
            collected.add(resolved);
            if (resolved.spec.isComposite) {
              collectAttributes(resolved.spec.fields);
            }
          }
        }
        if (attr.children.isNotEmpty) {
          collectAttributes(attr.children);
        }
      }
    }

    collectAttributes(objectSpec.attributes);
    return List<ResolvedValueObject>.unmodifiable(collected);
  }
}
