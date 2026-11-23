/// Service de promotion des objets métiers de la Spec vers les catalogues
/// [DomainContracts] des domaines fonctionnels de l'espace Design ([SpecDesignPromoter]).
library;

import 'package:flutter/foundation.dart';
import 'package:shortid/shortid.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/spec_forge_project.dart';

/// Stratégie de résolution lorsqu'une entrée de même nom technique existe déjà
/// dans le domaine cible.
enum PromotionConflictResolution {
  /// Met à jour les attributs, la description et le type DSL de l'entrée
  /// existante tout en conservant son identifiant et son historique de chat IA.
  updateExisting('Mettre à jour'),

  /// Conserve l'entrée existante intacte sans l'écraser.
  skipExisting('Ignorer');

  const PromotionConflictResolution(this.label);

  /// Libellé lisible affiché dans l'interface.
  final String label;
}

/// Choix unitaire de promotion d'un objet métier [objectId] vers un domaine Design.
@immutable
class ObjectPromotionChoice {
  /// Crée un choix de promotion pour [objectId].
  const ObjectPromotionChoice({
    required this.objectId,
    required this.domainId,
    required this.contractType,
    this.conflictResolution = PromotionConflictResolution.updateExisting,
  });

  /// Identifiant de l'objet métier source dans [SpecForgeProject.businessObjects].
  final String objectId;

  /// Identifiant du [FunctionalDomain] cible, ou `null` si l'objet n'est pas promu.
  final String? domainId;

  /// Type DSL cible dans [DomainContracts.types] (ex. `model`, `component`, `part`).
  final String contractType;

  /// Stratégie appliquée si l'objet existe déjà dans le domaine cible.
  final PromotionConflictResolution conflictResolution;

  /// Vrai si ce choix demande effectivement une promotion vers un domaine.
  bool get isSelected => domainId != null && domainId!.trim().isNotEmpty;

  /// Copie modifiée.
  ObjectPromotionChoice copyWith({
    String? objectId,
    String? domainId,
    bool clearDomainId = false,
    String? contractType,
    PromotionConflictResolution? conflictResolution,
  }) => ObjectPromotionChoice(
    objectId: objectId ?? this.objectId,
    domainId: clearDomainId ? null : (domainId ?? this.domainId),
    contractType: contractType ?? this.contractType,
    conflictResolution: conflictResolution ?? this.conflictResolution,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectPromotionChoice &&
          other.objectId == objectId &&
          other.domainId == domainId &&
          other.contractType == contractType &&
          other.conflictResolution == conflictResolution;

  @override
  int get hashCode =>
      Object.hash(objectId, domainId, contractType, conflictResolution);
}

/// Bilan des promotions réalisées sur un [FunctionalDomain] donné.
@immutable
class DomainPromotionSummary {
  /// Crée le bilan d'un domaine.
  DomainPromotionSummary({
    required this.domainId,
    required this.domainName,
    List<String> createdEntryIds = const <String>[],
    List<String> updatedEntryIds = const <String>[],
    List<String> skippedObjectNames = const <String>[],
  }) : createdEntryIds = List<String>.unmodifiable(createdEntryIds),
       updatedEntryIds = List<String>.unmodifiable(updatedEntryIds),
       skippedObjectNames = List<String>.unmodifiable(skippedObjectNames);

  /// Identifiant du domaine cible.
  final String domainId;

  /// Nom affiché du domaine cible.
  final String domainName;

  /// Identifiants des nouvelles entrées créées dans [DomainContracts].
  final List<String> createdEntryIds;

  /// Identifiants des entrées existantes mises à jour dans [DomainContracts].
  final List<String> updatedEntryIds;

  /// Noms des objets ignorés suite à un conflit en mode [PromotionConflictResolution.skipExisting].
  final List<String> skippedObjectNames;

  /// Vrai si le catalogue du domaine a été modifié (création ou mise à jour).
  bool get hasChanges =>
      createdEntryIds.isNotEmpty || updatedEntryIds.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainPromotionSummary &&
          other.domainId == domainId &&
          other.domainName == domainName &&
          listEquals(other.createdEntryIds, createdEntryIds) &&
          listEquals(other.updatedEntryIds, updatedEntryIds) &&
          listEquals(other.skippedObjectNames, skippedObjectNames);

  @override
  int get hashCode => Object.hash(
    domainId,
    domainName,
    Object.hashAll(createdEntryIds),
    Object.hashAll(updatedEntryIds),
    Object.hashAll(skippedObjectNames),
  );
}

/// Résultat global d'une opération de promotion vers Design.
@immutable
class PromotionExecutionResult {
  /// Crée un résultat global de promotion.
  PromotionExecutionResult({
    required this.updatedCatalog,
    List<DomainPromotionSummary> domainSummaries =
        const <DomainPromotionSummary>[],
  }) : domainSummaries = List<DomainPromotionSummary>.unmodifiable(
         domainSummaries,
       );

  /// Nouveau [DomainCatalog] validé incluant les [DomainContracts] et le journal d'audit mis à jour.
  final DomainCatalog updatedCatalog;

  /// Détail des opérations par domaine impacté.
  final List<DomainPromotionSummary> domainSummaries;

  /// Nombre total d'entrées nouvellement créées.
  int get createdCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.createdEntryIds.length,
  );

  /// Nombre total d'entrées existantes mises à jour.
  int get updatedCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.updatedEntryIds.length,
  );

  /// Nombre total d'objets ignorés suite à un conflit.
  int get skippedCount => domainSummaries.fold<int>(
    0,
    (sum, item) => sum + item.skippedObjectNames.length,
  );

  /// Premier domaine ayant reçu une création ou mise à jour (ou à défaut le premier domaine ciblé).
  String? get firstPromotedDomainId =>
      domainSummaries.where((s) => s.hasChanges).firstOrNull?.domainId ??
      domainSummaries.firstOrNull?.domainId;
}

/// Moteur pur de promotion des [BusinessObjectSpec] vers les [DomainContracts] de Design.
abstract final class SpecDesignPromoter {
  /// Type DSL par défaut suggéré pour un [BusinessObjectSpec] (`model` ou `component`).
  static String defaultContractTypeFor(BusinessObjectSpec object) =>
      object.aggregateRoot ? 'model' : 'component';

  /// Rubrique YAML cible associée à un [contractType] de [DomainContracts.types].
  static String defaultGroupForType(String contractType) =>
      switch (contractType) {
        'model' || 'part' => 'models',
        'component' => 'components',
        'eventxpayloaddto' || 'eventxenvelopedto' => 'message',
        _ => 'dto',
      };

  /// Recherche dans [contracts] une entrée existante de même nom technique que [technicalName]
  /// (comparaison insensible à la casse).
  static JsonNode? findExistingEntry(
    DomainContracts? contracts,
    String technicalName,
  ) {
    if (contracts == null) return null;
    final needle = technicalName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final group in contracts.groups) {
      for (final entry in group.children) {
        if (entry.name.toLowerCase() == needle ||
            DomainContracts.technicalNameOf(entry).toLowerCase() == needle) {
          return entry;
        }
      }
    }
    return null;
  }

  /// Compte le nombre de références ou relations sortantes de [object] dont la cible
  /// ne sera pas disponible dans [targetDomainId] (et sera donc convertie en identifiant scalaire).
  static int countExternalReferencesForObject({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required BusinessObjectSpec object,
    required String targetDomainId,
    required Map<String, String?> plannedDomainByObjectId,
  }) {
    final targetDomain = catalog.domains
        .where((d) => d.id == targetDomainId)
        .firstOrNull;
    final targetContracts = targetDomain?.contracts;

    bool isAvailableInTargetDomain(String rawRef) {
      final key = rawRef.trim();
      if (key.isEmpty) return true;
      final specTarget = _findSpecObject(project, key);
      if (specTarget != null) {
        if (specTarget.id == object.id) return true;
        if (plannedDomainByObjectId[specTarget.id] == targetDomainId) {
          return true;
        }
        if (findExistingEntry(targetContracts, specTarget.technicalName) !=
            null) {
          return true;
        }
        return false;
      }
      return findExistingEntry(targetContracts, key) != null;
    }

    var count = 0;
    void scanAttributes(List<BusinessAttribute> attrs) {
      for (final attr in attrs) {
        if (attr.type == BusinessAttributeType.reference &&
            !isAvailableInTargetDomain(attr.referenceObjectId)) {
          count++;
        }
        if (attr.children.isNotEmpty) {
          scanAttributes(attr.children);
        }
      }
    }

    scanAttributes(object.attributes);

    for (final rel in object.relations) {
      if (_hasEquivalentReferenceAttribute(object.attributes, rel, project)) {
        continue;
      }
      if (!isAvailableInTargetDomain(rel.targetObjectId)) {
        count++;
      }
    }
    return count;
  }

  /// Exécute la promotion des objets sélectionnés dans [choices] vers les domaines de [catalog].
  ///
  /// Fonctionne en deux passes par domaine :
  /// 1. Création ou mise à jour des entrées DSL et de leurs [ContractDetails] afin d'obtenir
  ///    les identifiants stables [JsonNode.id] de toutes les entrées du domaine.
  /// 2. Construction des [BusinessObjectSpec] cibles : recâblage des références intra-domaine
  ///    vers l'identifiant d'entrée cible et conversion des références/relations hors domaine
  ///    en identifiants scalaires documentés.
  static PromotionExecutionResult promote({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required List<ObjectPromotionChoice> choices,
    BusinessObjectModelPreferences? modelPreferences,
    String actorUsername = 'local-user',
    DateTime? now,
  }) {
    final effectivePrefs =
        modelPreferences ?? project.businessObjectModelPreferences;
    final timestamp = (now ?? DateTime.now()).toUtc();

    final activeChoices = <ObjectPromotionChoice>[];
    final plannedDomainBySpecObjectId = <String, String>{};
    for (final choice in choices) {
      if (!choice.isSelected) continue;
      if (!DomainContracts.types.contains(choice.contractType)) {
        throw FormatException(
          'Type de contrat inconnu : ${choice.contractType}.',
        );
      }
      final domainId = choice.domainId!.trim();
      if (!catalog.domains.any((d) => d.id == domainId)) {
        throw FormatException('Domaine cible introuvable : $domainId.');
      }
      final specObj = project.businessObjects
          .where((o) => o.id == choice.objectId)
          .firstOrNull;
      if (specObj == null) {
        throw FormatException(
          'Objet métier introuvable : ${choice.objectId}.',
        );
      }
      activeChoices.add(choice);
      plannedDomainBySpecObjectId[specObj.id] = domainId;
    }

    if (activeChoices.isEmpty) {
      return PromotionExecutionResult(updatedCatalog: catalog);
    }

    final choicesByDomain = <String, List<ObjectPromotionChoice>>{};
    for (final choice in activeChoices) {
      choicesByDomain
          .putIfAbsent(choice.domainId!.trim(), () => <ObjectPromotionChoice>[])
          .add(choice);
    }

    final summaries = <DomainPromotionSummary>[];
    final updatedDomains = <FunctionalDomain>[];
    final newAuditEvents = <AuditLogEntry>[];

    for (final domain in catalog.domains) {
      final domainChoices = choicesByDomain[domain.id];
      if (domainChoices == null || domainChoices.isEmpty) {
        updatedDomains.add(domain);
        continue;
      }

      var document = domain.contracts ?? DomainContracts.empty;
      final createdIds = <String>[];
      final updatedIds = <String>[];
      final skippedNames = <String>[];
      final pendingObjectWrites =
          <({BusinessObjectSpec specObject, String entryId})>[];

      // Passe 1 : création / mise à jour des entrées YAML et métadonnées ContractDetails.
      for (final choice in domainChoices) {
        final specObj = project.businessObjects.firstWhere(
          (o) => o.id == choice.objectId,
        );
        final existing = findExistingEntry(document, specObj.technicalName);
        if (existing != null) {
          if (choice.conflictResolution ==
              PromotionConflictResolution.skipExisting) {
            skippedNames.add(specObj.name);
            continue;
          }
          final prevDetails =
              document.details[existing.id] ?? ContractDetails.defaults;
          final prevStates = Map<ContractStage, ContractStatus>.from(
            prevDetails.states,
          );
          if ((prevStates[ContractStage.design] ?? ContractStatus.pending) ==
              ContractStatus.pending) {
            prevStates[ContractStage.design] = ContractStatus.inProgress;
          }
          final nextDetails = ContractDetails(
            title: specObj.name.trim(),
            version: prevDetails.version,
            states: prevStates,
          );
          document = document.edit(existing, choice.contractType, nextDetails);
          updatedIds.add(existing.id);
          pendingObjectWrites.add((
            specObject: specObj,
            entryId: existing.id,
          ));
        } else {
          final groupName = defaultGroupForType(choice.contractType);
          final nextSource = _insertEntryIntoYamlSource(
            document.source,
            groupName: groupName,
            entryName: specObj.technicalName,
            contractType: choice.contractType,
          );
          document = document.patch(nextSource);
          final created = findExistingEntry(document, specObj.technicalName);
          if (created == null) {
            throw FormatException(
              'Impossible de créer l’entrée DSL « ${specObj.technicalName} » dans le domaine « ${domain.name} ».',
            );
          }
          final details = ContractDetails(
            title: specObj.name.trim(),
            version: '0.0.1',
            states: const <ContractStage, ContractStatus>{
              ContractStage.design: ContractStatus.inProgress,
            },
          );
          document = document.edit(created, choice.contractType, details);
          createdIds.add(created.id);
          pendingObjectWrites.add((
            specObject: specObj,
            entryId: created.id,
          ));
        }
      }

      // Passe 2 : construction et attachement des BusinessObjectSpec résolus.
      for (final item in pendingObjectWrites) {
        final entry = document.entryById(item.entryId)!;
        final resolvedObject = _buildDomainObject(
          project: project,
          catalog: catalog,
          currentDomain: domain,
          currentDocument: document,
          entry: entry,
          specObject: item.specObject,
          plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
          modelPreferences: effectivePrefs,
        );
        document = document.withModel(item.entryId, object: resolvedObject);
      }

      final summary = DomainPromotionSummary(
        domainId: domain.id,
        domainName: domain.name,
        createdEntryIds: createdIds,
        updatedEntryIds: updatedIds,
        skippedObjectNames: skippedNames,
      );
      summaries.add(summary);

      if (summary.hasChanges) {
        updatedDomains.add(domain.copyWith(contracts: document));
        newAuditEvents.add(
          AuditLogEntry(
            id: 'audit_${shortid.generate()}',
            recordedAt: timestamp,
            actorUsername: actorUsername,
            domainId: domain.id,
            actionType: DomainAuditAction.update,
            details: _buildAuditDetails(project.name, summary),
          ),
        );
      } else {
        updatedDomains.add(domain);
      }
    }

    if (newAuditEvents.isEmpty) {
      return PromotionExecutionResult(
        updatedCatalog: catalog,
        domainSummaries: summaries,
      );
    }

    final nextCatalog = catalog.copyWith(
      domains: updatedDomains,
      auditLog: [...catalog.auditLog, ...newAuditEvents],
      updatedAt: timestamp,
    );
    nextCatalog.validate();

    return PromotionExecutionResult(
      updatedCatalog: nextCatalog,
      domainSummaries: summaries,
    );
  }

  static String _buildAuditDetails(
    String projectName,
    DomainPromotionSummary summary,
  ) {
    final parts = <String>[
      if (summary.createdEntryIds.isNotEmpty)
        '${summary.createdEntryIds.length} créé(s)',
      if (summary.updatedEntryIds.isNotEmpty)
        '${summary.updatedEntryIds.length} mis à jour',
      if (summary.skippedObjectNames.isNotEmpty)
        '${summary.skippedObjectNames.length} ignoré(s)',
    ];
    final raw = 'Promotion Spec « $projectName » : ${parts.join(', ')}';
    return raw.length <= 2000 ? raw : raw.substring(0, 2000);
  }

  /// Insère `  <entryName>: <contractType>` sous la rubrique `<groupName>:` de [source]
  /// sans altérer les commentaires ni les autres entrées existantes.
  static String _insertEntryIntoYamlSource(
    String source, {
    required String groupName,
    required String entryName,
    required String contractType,
  }) {
    final normalized = source.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) {
      return '$groupName:\n  $entryName: $contractType\n';
    }

    final lines = normalized.split('\n');
    // Retire l'élément vide final dû au '\n' terminal pour simplifier l'indexation.
    final hadTrailingNewline = lines.isNotEmpty && lines.last.isEmpty;
    if (hadTrailingNewline) {
      lines.removeLast();
    }

    final headerPattern = RegExp(
      '^${RegExp.escape(groupName)}\\s*:(?:\\s*(?:#.*)?)?\$',
    );
    final topLevelLinePattern = RegExp(r'^[^\s#]');
    final childEntryPattern = RegExp(r'^\s+[^\s#]');

    var groupLineIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (headerPattern.hasMatch(lines[i])) {
        groupLineIndex = i;
        break;
      }
    }

    final entryLine = '  $entryName: $contractType';
    if (groupLineIndex >= 0) {
      var nextTopLevelIndex = lines.length;
      for (var i = groupLineIndex + 1; i < lines.length; i++) {
        if (topLevelLinePattern.hasMatch(lines[i])) {
          nextTopLevelIndex = i;
          break;
        }
      }
      var lastChildIndex = -1;
      for (var i = groupLineIndex + 1; i < nextTopLevelIndex; i++) {
        if (childEntryPattern.hasMatch(lines[i])) {
          lastChildIndex = i;
        }
      }
      final insertAt = lastChildIndex >= 0 ? lastChildIndex + 1 : groupLineIndex + 1;
      lines.insert(insertAt, entryLine);
    } else {
      if (lines.isNotEmpty && lines.last.trim().isNotEmpty) {
        lines.add('');
      }
      lines
        ..add('$groupName:')
        ..add(entryLine);
    }

    return '${lines.join('\n')}\n';
  }

  static BusinessObjectSpec _buildDomainObject({
    required SpecForgeProject project,
    required DomainCatalog catalog,
    required FunctionalDomain currentDomain,
    required DomainContracts currentDocument,
    required JsonNode entry,
    required BusinessObjectSpec specObject,
    required Map<String, String> plannedDomainBySpecObjectId,
    required BusinessObjectModelPreferences modelPreferences,
  }) {
    String? resolveSameDomainEntryId(String rawTarget) {
      final key = rawTarget.trim();
      if (key.isEmpty) return null;
      final targetSpec = _findSpecObject(project, key);
      if (targetSpec != null) {
        if (targetSpec.id == specObject.id) return entry.id;
        final matchInDoc = findExistingEntry(
          currentDocument,
          targetSpec.technicalName,
        );
        if (matchInDoc != null) return matchInDoc.id;
        return null;
      }
      return findExistingEntry(currentDocument, key)?.id;
    }

    BusinessAttribute transformAttribute(BusinessAttribute attr) {
      final transformedChildren = <BusinessAttribute>[
        for (final child in attr.children) transformAttribute(child),
      ];
      if (attr.type != BusinessAttributeType.reference) {
        return attr.copyWith(children: transformedChildren);
      }
      final sameDomainTargetId = resolveSameDomainEntryId(
        attr.referenceObjectId,
      );
      if (sameDomainTargetId != null) {
        return attr.copyWith(
          referenceObjectId: sameDomainTargetId,
          children: transformedChildren,
        );
      }
      final targetSpec = _findSpecObject(project, attr.referenceObjectId);
      final scalarType = _scalarIdTypeForTarget(targetSpec, modelPreferences);
      final note = _externalReferenceNote(
        rawTarget: attr.referenceObjectId,
        targetSpec: targetSpec,
        catalog: catalog,
        currentDomainId: currentDomain.id,
        plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
      );
      return attr.copyWith(
        type: scalarType,
        referenceObjectId: '',
        description: _appendNote(attr.description, note),
        children: transformedChildren,
      );
    }

    final mergedAttributes = <BusinessAttribute>[
      for (final attr in specObject.attributes) transformAttribute(attr),
    ];
    final usedNamesLower = <String>{
      for (final attr in mergedAttributes) attr.name.toLowerCase(),
    };

    for (final rel in specObject.relations) {
      if (_hasEquivalentReferenceAttribute(
        specObject.attributes,
        rel,
        project,
      )) {
        continue;
      }
      if (mergedAttributes.length >= BusinessObjectSpec.maxAttributesPerObject) {
        break;
      }
      final attrName = _uniqueAttributeName(rel.name, usedNamesLower);
      usedNamesLower.add(attrName.toLowerCase());
      final isArray =
          rel.cardinality == BusinessRelationCardinality.oneToMany ||
          rel.cardinality == BusinessRelationCardinality.manyToMany;
      final sameDomainTargetId = resolveSameDomainEntryId(rel.targetObjectId);
      if (sameDomainTargetId != null) {
        mergedAttributes.add(
          BusinessAttribute(
            id: 'attr_${rel.id}',
            name: attrName,
            type: BusinessAttributeType.reference,
            referenceObjectId: sameDomainTargetId,
            isArray: isArray,
            required: rel.required,
            description: rel.description,
          ),
        );
      } else {
        final targetSpec = _findSpecObject(project, rel.targetObjectId);
        final scalarType = _scalarIdTypeForTarget(targetSpec, modelPreferences);
        final note = _externalReferenceNote(
          rawTarget: rel.targetObjectId,
          targetSpec: targetSpec,
          catalog: catalog,
          currentDomainId: currentDomain.id,
          plannedDomainBySpecObjectId: plannedDomainBySpecObjectId,
        );
        mergedAttributes.add(
          BusinessAttribute(
            id: 'attr_${rel.id}',
            name: attrName,
            type: scalarType,
            referenceObjectId: '',
            isArray: isArray,
            required: rel.required,
            description: _appendNote(rel.description, note),
          ),
        );
      }
    }

    final result = BusinessObjectSpec(
      id: entry.id,
      name: specObject.name,
      technicalName: DomainContracts.technicalNameOf(entry),
      description: specObject.description,
      aggregateRoot: specObject.aggregateRoot,
      attributes: mergedAttributes,
      relations: const <BusinessRelation>[],
      lifecycleStates: specObject.lifecycleStates,
      lifecycleTransitions: specObject.lifecycleTransitions,
    );
    result.validate();
    return result;
  }

  static BusinessObjectSpec? _findSpecObject(
    SpecForgeProject project,
    String rawIdOrTechName,
  ) {
    final needle = rawIdOrTechName.trim();
    if (needle.isEmpty) return null;
    return project.findBusinessObject(needle) ??
        project.businessObjects
            .where(
              (o) =>
                  o.id.toLowerCase() == needle.toLowerCase() ||
                  o.technicalName.toLowerCase() == needle.toLowerCase(),
            )
            .firstOrNull;
  }

  static bool _hasEquivalentReferenceAttribute(
    List<BusinessAttribute> attributes,
    BusinessRelation rel,
    SpecForgeProject project,
  ) {
    final relIsArray =
        rel.cardinality == BusinessRelationCardinality.oneToMany ||
        rel.cardinality == BusinessRelationCardinality.manyToMany;
    final relTarget = _findSpecObject(project, rel.targetObjectId);
    for (final attr in attributes) {
      if (attr.name.toLowerCase() == rel.name.toLowerCase()) {
        return true;
      }
      if (attr.type == BusinessAttributeType.reference &&
          attr.isArray == relIsArray) {
        if (attr.referenceObjectId.trim().toLowerCase() ==
            rel.targetObjectId.trim().toLowerCase()) {
          return true;
        }
        final attrTarget = _findSpecObject(project, attr.referenceObjectId);
        if (relTarget != null && attrTarget?.id == relTarget.id) {
          return true;
        }
      }
    }
    return false;
  }

  static String _uniqueAttributeName(String rawBase, Set<String> usedLower) {
    final base = BusinessAttribute.isValidDslIdentifier(rawBase)
        ? rawBase
        : BusinessAttribute.normalizeDslIdentifier(rawBase, fallback: 'ref');
    if (!usedLower.contains(base.toLowerCase())) return base;
    for (var i = 2; ; i++) {
      final candidate = '${base}_$i';
      if (!usedLower.contains(candidate.toLowerCase())) return candidate;
    }
  }

  static BusinessAttributeType _scalarIdTypeForTarget(
    BusinessObjectSpec? targetSpec,
    BusinessObjectModelPreferences prefs,
  ) {
    if (targetSpec != null) {
      final pk =
          targetSpec.attributes
              .where((a) => !a.isArray && a.name.toLowerCase() == 'id')
              .firstOrNull ??
          targetSpec.attributes
              .where((a) => !a.isArray && a.unique && a.required)
              .firstOrNull;
      if (pk != null) {
        switch (pk.type) {
          case BusinessAttributeType.uuid:
          case BusinessAttributeType.integer:
          case BusinessAttributeType.string:
          case BusinessAttributeType.number:
            return pk.type;
          default:
            break;
        }
      }
    }
    return switch (prefs.idStrategy) {
      PrimaryIdStrategy.uuid => BusinessAttributeType.uuid,
      PrimaryIdStrategy.autoIncrementInt => BusinessAttributeType.integer,
      PrimaryIdStrategy.ulid ||
      PrimaryIdStrategy.businessKeyOnly ||
      PrimaryIdStrategy.none => BusinessAttributeType.string,
    };
  }

  static String _externalReferenceNote({
    required String rawTarget,
    required BusinessObjectSpec? targetSpec,
    required DomainCatalog catalog,
    required String currentDomainId,
    required Map<String, String> plannedDomainBySpecObjectId,
  }) {
    final targetLabel = targetSpec?.name ??
        (rawTarget.trim().isNotEmpty ? rawTarget.trim() : 'entité externe');
    String? otherDomainName;
    if (targetSpec != null) {
      final plannedDomainId = plannedDomainBySpecObjectId[targetSpec.id];
      if (plannedDomainId != null && plannedDomainId != currentDomainId) {
        otherDomainName = catalog.domains
            .where((d) => d.id == plannedDomainId)
            .firstOrNull
            ?.name;
      }
      otherDomainName ??= catalog.domains
          .where(
            (d) =>
                d.id != currentDomainId &&
                findExistingEntry(d.contracts, targetSpec.technicalName) !=
                    null,
          )
          .firstOrNull
          ?.name;
    }
    return otherDomainName != null
        ? 'Référence externe vers $targetLabel (domaine $otherDomainName)'
        : 'Référence externe vers $targetLabel';
  }

  static String _appendNote(String existingDescription, String note) {
    final clean = existingDescription.trim();
    if (clean.isEmpty) return note;
    if (clean.toLowerCase().contains(note.toLowerCase())) return clean;
    return '$clean — $note';
  }
}
