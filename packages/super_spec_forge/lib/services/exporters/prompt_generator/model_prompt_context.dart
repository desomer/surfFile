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

  /// Extrait et résout le contexte complet de [item] dans [domain].
  factory ModelPromptContext.resolve({
    required FunctionalDomain domain,
    required BuildDesignItem item,
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
    );
  }
}
