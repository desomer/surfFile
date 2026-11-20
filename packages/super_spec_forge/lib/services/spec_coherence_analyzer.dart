/// Analyseur déterministe de cohérence inter-étapes ([SpecCoherenceAnalyzer]).
library;

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';

/// Vérifie la cohérence référentielle et la complétude d'un [SpecForgeProject].
abstract final class SpecCoherenceAnalyzer {
  /// Exécute tous les contrôles statiques sur [project] et retourne les diagnostics triés.
  static List<SpecCoherenceIssue> analyze(SpecForgeProject project) {
    final issues = <SpecCoherenceIssue>[];

    // 1. Contrôles de cadrage (Étape 1)
    if (project.vision.personas.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_no_personas',
          severity: CoherenceSeverity.warning,
          stage: SpecForgeStage.vision,
          code: 'COH-VIS-001',
          title: 'Aucun acteur / persona défini',
          description:
              'Aucun persona n’est encore rattaché au cadrage du produit.',
          suggestion:
              'Ajoutez au moins un rôle utilisateur pour relier les exigences et habilitations.',
        ),
      );
    }
    if (project.vision.objectives.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_no_objectives',
          severity: CoherenceSeverity.info,
          stage: SpecForgeStage.vision,
          code: 'COH-VIS-002',
          title: 'Objectifs stratégiques non listés',
          description:
              'Les objectifs mesurables facilitent la priorisation MoSCoW.',
          suggestion: 'Renseignez 2 à 4 objectifs clés dans l’étape Cadrage.',
        ),
      );
    }

    // 2. Contrôles du cahier des charges (Étape 2)
    final personaIds = {for (final p in project.vision.personas) p.id};
    final moduleIds = {
      for (final m in project.cahierDesCharges.modules) m.id,
    };

    if (project.cahierDesCharges.functionalRequirements.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_no_exf',
          severity: CoherenceSeverity.warning,
          stage: SpecForgeStage.specifications,
          code: 'COH-CDC-001',
          title: 'Aucune exigence fonctionnelle',
          description:
              'Le cahier des charges ne contient pas encore d’exigence fonctionnelle (EXF).',
          suggestion:
              'Complétez l’étape 2 avec l’agent Business Analyst ou ajoutez des exigences.',
        ),
      );
    }

    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (req.moduleId.isNotEmpty && !moduleIds.contains(req.moduleId)) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_req_mod_${req.id}',
            severity: CoherenceSeverity.error,
            stage: SpecForgeStage.specifications,
            code: 'COH-CDC-002',
            title: 'Module introuvable sur ${req.code}',
            description:
                'L’exigence « ${req.title} » référence un module inexistant (${req.moduleId}).',
            targetRef: req.code,
            suggestion: 'Associez un module existant ou créez le module manquant.',
          ),
        );
      }
      for (final actorId in req.actorIds) {
        if (personaIds.isNotEmpty && !personaIds.contains(actorId)) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_req_actor_${req.id}_$actorId',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.specifications,
              code: 'COH-CDC-003',
              title: 'Acteur inconnu sur ${req.code}',
              description:
                  'L’exigence « ${req.title} » cite l’acteur « $actorId » absent du cadrage.',
              targetRef: req.code,
              suggestion: 'Ajoutez ce persona à l’étape 1 ou corrigez l’identifiant.',
            ),
          );
        }
      }
    }

    // 3. Contrôles des objets métiers (Étape 3)
    final objectIds = {for (final o in project.businessObjects) o.id};
    final objectsByAnyKey = <String, BusinessObjectSpec>{};
    for (final obj in project.businessObjects) {
      objectsByAnyKey[obj.id.toLowerCase()] = obj;
      objectsByAnyKey[obj.technicalName.toLowerCase()] = obj;
      objectsByAnyKey[obj.name.toLowerCase()] = obj;
    }

    if (project.businessObjects.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_no_objects',
          severity: CoherenceSeverity.warning,
          stage: SpecForgeStage.businessObjects,
          code: 'COH-OBJ-001',
          title: 'Aucun objet métier modélisé',
          description: 'Le modèle du domaine est actuellement vide.',
          suggestion:
              'Utilisez l’agent Domain Modeler (étape 3) pour définir les entités principales.',
        ),
      );
    }

    for (final obj in project.businessObjects) {
      if (obj.attributes.isEmpty) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_obj_no_attrs_${obj.id}',
            severity: CoherenceSeverity.warning,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-OBJ-002',
            title: 'Objet sans attribut : ${obj.name}',
            description:
                'L’objet « ${obj.name} » (${obj.technicalName}) ne possède aucun attribut typé.',
            targetRef: obj.id,
            suggestion: 'Ajoutez au moins un identifiant et des propriétés métier.',
          ),
        );
      }

      for (final attr in obj.attributes) {
        if (attr.type == BusinessAttributeType.enumeration &&
            attr.enumValues.isEmpty) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_attr_enum_${obj.id}_${attr.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.businessObjects,
              code: 'COH-OBJ-003',
              title: 'Énumération vide : ${obj.technicalName}.${attr.name}',
              description:
                  'L’attribut « ${attr.name} » est de type énumération mais aucune valeur n’est définie.',
              targetRef: '${obj.id}.${attr.name}',
              suggestion: 'Listez les valeurs autorisées dans enumValues.',
            ),
          );
        }
        if (attr.type == BusinessAttributeType.reference &&
            attr.referenceObjectId.isNotEmpty &&
            !objectsByAnyKey.containsKey(
              attr.referenceObjectId.toLowerCase(),
            )) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_attr_ref_${obj.id}_${attr.id}',
              severity: CoherenceSeverity.error,
              stage: SpecForgeStage.businessObjects,
              code: 'COH-OBJ-004',
              title:
                  'Référence cassée : ${obj.technicalName}.${attr.name}',
              description:
                  'L’attribut « ${attr.name} » référence l’objet inconnu « ${attr.referenceObjectId} ».',
              targetRef: '${obj.id}.${attr.name}',
              suggestion: 'Créez l’objet cible ou corrigez referenceObjectId.',
            ),
          );
        }
      }

      for (final rel in obj.relations) {
        if (!objectIds.contains(rel.targetObjectId) &&
            !objectsByAnyKey.containsKey(rel.targetObjectId.toLowerCase())) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_rel_target_${obj.id}_${rel.id}',
              severity: CoherenceSeverity.error,
              stage: SpecForgeStage.businessObjects,
              code: 'COH-OBJ-005',
              title: 'Relation vers objet inconnu : ${obj.technicalName}.${rel.name}',
              description:
                  'La relation « ${rel.name} » pointe vers « ${rel.targetObjectId} » qui n’existe pas.',
              targetRef: '${obj.id}.${rel.name}',
              suggestion: 'Ajoutez l’entité cible ou mettez à jour la relation.',
            ),
          );
        }
      }

      if (obj.lifecycleStates.isNotEmpty) {
        final stateNames = {for (final s in obj.lifecycleStates) s.name};
        if (!obj.lifecycleStates.any((s) => s.isInitial)) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_lifecycle_init_${obj.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.businessObjects,
              code: 'COH-OBJ-006',
              title: 'Aucun état initial sur ${obj.name}',
              description:
                  'Le cycle de vie de « ${obj.name} » comporte ${obj.lifecycleStates.length} état(s) mais aucun état initial.',
              targetRef: obj.id,
              suggestion: 'Marquez un état avec isInitial = true.',
            ),
          );
        }
        for (final tr in obj.lifecycleTransitions) {
          if (!stateNames.contains(tr.fromState) ||
              !stateNames.contains(tr.toState)) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_lifecycle_tr_${obj.id}_${tr.id}',
                severity: CoherenceSeverity.error,
                stage: SpecForgeStage.businessObjects,
                code: 'COH-OBJ-007',
                title: 'Transition invalide sur ${obj.name}',
                description:
                    'La transition ${tr.fromState} -> ${tr.toState} référence un état non déclaré.',
                targetRef: obj.id,
                suggestion: 'Déclarez les deux états dans lifecycleStates.',
              ),
            );
          }
        }
      }
    }

    // 4. Contrôles des règles de gestion (Étape 4)
    if (project.businessRules.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_no_rules',
          severity: CoherenceSeverity.warning,
          stage: SpecForgeStage.businessRules,
          code: 'COH-RG-001',
          title: 'Aucune règle de gestion formalisée',
          description:
              'Aucune règle RG-xxx n’a encore été rattachée aux objets métiers.',
          suggestion:
              'Passez par l’étape 4 (Rule Architect) pour formaliser validations, calculs et transitions.',
        ),
      );
    }

    final seenCodes = <String>{};
    for (final rule in project.businessRules) {
      if (!seenCodes.add(rule.code.toUpperCase())) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_rg_dup_${rule.id}',
            severity: CoherenceSeverity.warning,
            stage: SpecForgeStage.businessRules,
            code: 'COH-RG-002',
            title: 'Code de règle dupliqué : ${rule.code}',
            description:
                'Plusieurs règles partagent le code « ${rule.code} ».',
            targetRef: rule.id,
            suggestion: 'Rendez chaque code RG-xxx unique.',
          ),
        );
      }

      if (rule.targetObjectIds.isEmpty) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_rg_no_obj_${rule.id}',
            severity: CoherenceSeverity.info,
            stage: SpecForgeStage.businessRules,
            code: 'COH-RG-003',
            title: 'Règle non rattachée : ${rule.code}',
            description:
                'La règle « ${rule.title} » n’est liée à aucun objet métier.',
            targetRef: rule.code,
            suggestion: 'Associez au moins un objet dans targetObjectIds.',
          ),
        );
      }

      for (final targetId in rule.targetObjectIds) {
        final target = objectsByAnyKey[targetId.toLowerCase()];
        if (target == null) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_rg_missing_obj_${rule.id}_$targetId',
              severity: CoherenceSeverity.error,
              stage: SpecForgeStage.businessRules,
              code: 'COH-RG-004',
              title: 'Objet cible inconnu sur ${rule.code}',
              description:
                  'La règle « ${rule.title} » cible « $targetId » qui n’existe pas dans les objets métiers.',
              targetRef: rule.code,
              suggestion: 'Créez l’objet manquant ou corrigez targetObjectIds.',
            ),
          );
        } else if (rule.category == BusinessRuleCategory.stateTransition &&
            target.lifecycleStates.isEmpty) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_rg_no_lifecycle_${rule.id}_${target.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.businessRules,
              code: 'COH-RG-005',
              title: 'Transition sans cycle de vie sur ${rule.code}',
              description:
                  'La règle de transition ${rule.code} cible « ${target.name} », qui n’a aucun état défini.',
              targetRef: rule.code,
              suggestion: 'Définissez les états du cycle de vie sur « ${target.name} ».',
            ),
          );
        }
      }
    }

    issues.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return List<SpecCoherenceIssue>.unmodifiable(issues);
  }
}
