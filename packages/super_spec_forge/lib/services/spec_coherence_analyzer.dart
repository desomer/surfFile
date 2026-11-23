/// Analyseur déterministe de cohérence inter-étapes ([SpecCoherenceAnalyzer]).
library;

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/event_storming_spec.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';

/// Vérifie la cohérence référentielle et la complétude d'un [SpecForgeProject].
abstract final class SpecCoherenceAnalyzer {
  /// Exécute tous les contrôles statiques sur [project] (et optionnellement contre [companyGlossary]
  /// et [modelPreferences]) et retourne les diagnostics triés.
  static List<SpecCoherenceIssue> analyze(
    SpecForgeProject project, {
    CompanyGlossary? companyGlossary,
    BusinessObjectModelPreferences? modelPreferences,
  }) {
    final issues = <SpecCoherenceIssue>[];

    // 0. Contrôles du lexique métier (Étape 1)
    if (project.lexicon.terms.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_no_lexicon',
          severity: CoherenceSeverity.info,
          stage: SpecForgeStage.lexicon,
          code: 'COH-LEX-001',
          title: 'Lexique métier vide',
          description:
              'Aucun terme métier canonique n’est encore défini dans le lexique.',
          suggestion:
              'Définissez les termes clés dès l’étape 1 pour unifier le vocabulaire du cahier des charges et des objets.',
        ),
      );
    } else {
      final seenTerms = <String>{};
      for (final term in project.lexicon.terms) {
        if (!seenTerms.add(term.term.trim().toLowerCase())) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_lex_dup_${term.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.lexicon,
              code: 'COH-LEX-002',
              title: 'Terme dupliqué dans le lexique : ${term.term}',
              description:
                  'Le terme « ${term.term} » apparaît plusieurs fois dans le lexique métier.',
              targetRef: term.id,
              suggestion: 'Fusionnez les entrées ou précisez leurs synonymes.',
            ),
          );
        }
        if (term.definition.trim().isEmpty) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_lex_def_${term.id}',
              severity: CoherenceSeverity.info,
              stage: SpecForgeStage.lexicon,
              code: 'COH-LEX-003',
              title: 'Définition manquante : ${term.term}',
              description:
                  'Le terme « ${term.term} » ne possède pas encore de définition métier.',
              targetRef: term.id,
              suggestion: 'Ajoutez une définition univoque.',
            ),
          );
        }
      }
    }

    // 0 bis. Contrôles croisés avec le glossaire d'entreprise global
    if (companyGlossary != null && companyGlossary.terms.isNotEmpty) {
      final forbiddenMap = <String, CompanyGlossaryTerm>{};
      final deprecatedMap = <String, CompanyGlossaryTerm>{};
      for (final cgTerm in companyGlossary.terms) {
        if (cgTerm.status == CompanyGlossaryStatus.deprecated) {
          deprecatedMap[cgTerm.term.trim().toLowerCase()] = cgTerm;
        } else {
          for (final forbidden in cgTerm.forbiddenTerms) {
            final key = forbidden.trim().toLowerCase();
            if (key.isNotEmpty) {
              forbiddenMap[key] = cgTerm;
            }
          }
        }
      }

      for (final lexTerm in project.lexicon.terms) {
        final key = lexTerm.term.trim().toLowerCase();
        final forbiddenHit = forbiddenMap[key];
        if (forbiddenHit != null) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_cg_forbidden_lex_${lexTerm.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.lexicon,
              code: 'COH-LEX-004',
              title: 'Terme proscrit par l’entreprise : ${lexTerm.term}',
              description:
                  'Le terme « ${lexTerm.term} » du lexique projet est proscrit par le glossaire d’entreprise au profit de « ${forbiddenHit.term} ».',
              targetRef: lexTerm.id,
              suggestion:
                  'Remplacez-le par le terme canonique « ${forbiddenHit.term} » et conservez « ${lexTerm.term} » en synonyme si utile.',
            ),
          );
        }
        final deprecatedHit = deprecatedMap[key];
        if (deprecatedHit != null) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_cg_deprecated_lex_${lexTerm.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.lexicon,
              code: 'COH-LEX-005',
              title: 'Terme d’entreprise déprécié : ${lexTerm.term}',
              description:
                  'Le terme « ${lexTerm.term} » est marqué comme déprécié dans le glossaire d’entreprise.',
              targetRef: lexTerm.id,
              suggestion:
                  'Vérifiez le terme de remplacement recommandé dans le glossaire d’entreprise.',
            ),
          );
        }
      }

      for (final obj in project.businessObjects) {
        final key = obj.name.trim().toLowerCase();
        final forbiddenHit = forbiddenMap[key];
        if (forbiddenHit != null) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_cg_forbidden_obj_${obj.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.businessObjects,
              code: 'COH-LEX-004',
              title: 'Objet nommé avec un terme proscrit : ${obj.name}',
              description:
                  'L’objet métier « ${obj.name} » utilise un terme proscrit par le glossaire d’entreprise (terme officiel : « ${forbiddenHit.term} »).',
              targetRef: obj.id,
              suggestion:
                  'Renommez l’objet en « ${forbiddenHit.term} »${forbiddenHit.technicalNameHint.isNotEmpty ? ' (${forbiddenHit.technicalNameHint})' : ''}.',
            ),
          );
        }
      }
    }

    // 1. Contrôles de cadrage (Étape 2)
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

    // 3. Contrôles des objets métiers (Étape 5)
    final objectIds = {for (final o in project.businessObjects) o.id};
    final objectsByAnyKey = <String, BusinessObjectSpec>{};
    for (final obj in project.businessObjects) {
      objectsByAnyKey[obj.id.toLowerCase()] = obj;
      objectsByAnyKey[obj.technicalName.toLowerCase()] = obj;
      objectsByAnyKey[obj.name.toLowerCase()] = obj;
    }

    // 2 bis. Contrôles d'Event Storming (Étape 4)
    final es = project.eventStorming;
    if (es.hasContent && es.flows.isEmpty) {
      issues.add(
        const SpecCoherenceIssue(
          id: 'coh_es_empty',
          severity: CoherenceSeverity.info,
          stage: SpecForgeStage.eventStorming,
          code: 'COH-ES-001',
          title: 'Contextes bornés sans flux Event Storming',
          description:
              'Des Bounded Contexts sont déclarés, mais aucun flux chronologique d’événements, commandes et agrégats n’a encore été défini.',
          suggestion:
              'Amorcez l’Event Storming depuis le Cahier des charges pour faire émerger vos agrégats et politiques.',
        ),
      );
    } else if (es.flows.isNotEmpty) {
      final rulesByIdOrCode = <String, BusinessRuleSpec>{
        for (final r in project.businessRules) ...{
          r.id.toLowerCase(): r,
          r.code.toLowerCase(): r,
        },
      };

      for (final flow in es.flows) {
        if (flow.domainEventCount == 0) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_es_no_evt_${flow.id}',
              severity: CoherenceSeverity.info,
              stage: SpecForgeStage.eventStorming,
              code: 'COH-ES-003',
              title: 'Flux sans événement domaine : ${flow.code}',
              description:
                  'Le flux « ${flow.title} » ne contient aucun événement domaine (carte orange).',
              targetRef: flow.id,
              suggestion:
                  'Ajoutez au moins un événement métier formulé au passé pour matérialiser le résultat du flux.',
            ),
          );
        }

        if (flow.openHotspotCount > 0) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_es_open_hot_${flow.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.eventStorming,
              code: 'COH-ES-002',
              title:
                  '${flow.openHotspotCount} hotspot(s) ouvert(s) dans ${flow.code}',
              description:
                  'Le flux « ${flow.title} » comporte encore ${flow.openHotspotCount} zone(s) d’ombre non tranchée(s).',
              targetRef: flow.id,
              suggestion:
                  'Résolvez les hotspots rouges avec l’Event Storming Facilitator ou documentez la décision.',
            ),
          );
        }

        final nodeIds = {for (final n in flow.nodes) n.id};
        for (final link in flow.links) {
          if (!nodeIds.contains(link.fromNodeId) ||
              !nodeIds.contains(link.toNodeId)) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_es_dangling_link_${flow.id}_${link.id}',
                severity: CoherenceSeverity.warning,
                stage: SpecForgeStage.eventStorming,
                code: 'COH-ES-005',
                title: 'Liaison incomplète dans ${flow.code}',
                description:
                    'Une liaison (${link.fromNodeId} → ${link.toNodeId}) pointe vers une carte absente du flux.',
                targetRef: flow.id,
                suggestion: 'Supprimez ou recâblez cette liaison.',
              ),
            );
          }
        }

        for (final node in flow.nodes) {
          if (node.kind == EventStormNodeKind.aggregate &&
              project.businessObjects.isNotEmpty) {
            final key = node.targetObjectId.trim().isNotEmpty
                ? node.targetObjectId.trim().toLowerCase()
                : node.title.trim().toLowerCase();
            final pascalKey = node.title
                .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '')
                .toLowerCase();
            if (!objectsByAnyKey.containsKey(key) &&
                !objectsByAnyKey.containsKey(pascalKey)) {
              issues.add(
                SpecCoherenceIssue(
                  id: 'coh_es_agg_unmapped_${flow.id}_${node.id}',
                  severity: CoherenceSeverity.warning,
                  stage: SpecForgeStage.eventStorming,
                  code: 'COH-ES-004',
                  title: 'Agrégat non modélisé en objet : ${node.title}',
                  description:
                      'L’agrégat « ${node.title} » du flux ${flow.code} ne correspond à aucun objet métier de l’étape 5.',
                  targetRef: flow.id,
                  suggestion:
                      'Utilisez « Générer Objets métiers » ou rattachez cet agrégat à un objet existant.',
                ),
              );
            }
          }

          if (node.kind == EventStormNodeKind.policy &&
              node.linkedRuleId.trim().isNotEmpty &&
              !rulesByIdOrCode.containsKey(
                node.linkedRuleId.trim().toLowerCase(),
              )) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_es_missing_rule_${flow.id}_${node.id}',
                severity: CoherenceSeverity.warning,
                stage: SpecForgeStage.eventStorming,
                code: 'COH-ES-004',
                title: 'Lien RG cassé sur politique (${node.linkedRuleId})',
                description:
                    'La politique « ${node.title} » dans ${flow.code} référence la règle « ${node.linkedRuleId} », introuvable dans les règles de gestion.',
                targetRef: flow.id,
                suggestion: 'Promouvez à nouveau cette politique en règle RG-xxx.',
              ),
            );
          }
        }
      }
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

      final totalAttrs = obj.totalAttributeCount;
      if (totalAttrs > BusinessObjectSpec.maxAttributesPerObject) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_obj_max_attrs_${obj.id}',
            severity: CoherenceSeverity.error,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-OBJ-008',
            title: 'Limite de 200 attributs dépassée : ${obj.name}',
            description:
                'L’objet « ${obj.name} » totalise $totalAttrs attributs (max ${BusinessObjectSpec.maxAttributesPerObject}).',
            targetRef: obj.id,
            suggestion: 'Scindez cet objet en plusieurs objets métiers distincts.',
          ),
        );
      } else if (totalAttrs >= 160) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_obj_warn_attrs_${obj.id}',
            severity: CoherenceSeverity.warning,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-OBJ-008',
            title: 'Objet proche du plafond de 200 attributs : ${obj.name}',
            description:
                'L’objet « ${obj.name} » contient déjà $totalAttrs/${BusinessObjectSpec.maxAttributesPerObject} attributs.',
            targetRef: obj.id,
            suggestion: 'Envisagez de déléguer certains sous-objets vers un objet métier séparé.',
          ),
        );
      }

      void checkAttributes(List<BusinessAttribute> attrs, String prefix) {
        for (final attr in attrs) {
          final qualified = '$prefix.${attr.name}';
          if (attr.type == BusinessAttributeType.enumeration &&
              attr.enumValues.isEmpty) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_attr_enum_${obj.id}_${attr.id}',
                severity: CoherenceSeverity.warning,
                stage: SpecForgeStage.businessObjects,
                code: 'COH-OBJ-003',
                title: 'Énumération vide : $qualified',
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
                title: 'Référence cassée : $qualified',
                description:
                    'L’attribut « ${attr.name} » référence l’objet inconnu « ${attr.referenceObjectId} ».',
                targetRef: '${obj.id}.${attr.name}',
                suggestion: 'Créez l’objet cible ou corrigez referenceObjectId.',
              ),
            );
          }
          if (attr.type == BusinessAttributeType.object &&
              attr.children.isEmpty) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_attr_empty_obj_${obj.id}_${attr.id}',
                severity: CoherenceSeverity.warning,
                stage: SpecForgeStage.businessObjects,
                code: 'COH-OBJ-010',
                title: 'Sous-objet vide : $qualified',
                description:
                    'Le sous-objet « ${attr.name} » ne contient aucun sous-attribut.',
                targetRef: '${obj.id}.${attr.name}',
                suggestion: 'Ajoutez ses champs ou passez son type en json libre.',
              ),
            );
          }
          if (attr.isArray) {
            if (attr.estimatedMaxRows != null &&
                attr.estimatedMaxRows! >
                    BusinessObjectSpec.maxEmbeddedArrayRows) {
              issues.add(
                SpecCoherenceIssue(
                  id: 'coh_attr_rows_${obj.id}_${attr.id}',
                  severity: CoherenceSeverity.error,
                  stage: SpecForgeStage.businessObjects,
                  code: 'COH-OBJ-009',
                  title: 'Tableau imbriqué > 200 lignes : $qualified',
                  description:
                      'Le tableau « ${attr.name} » prévoit ${attr.estimatedMaxRows} lignes (> ${BusinessObjectSpec.maxEmbeddedArrayRows}).',
                  targetRef: '${obj.id}.${attr.name}',
                  suggestion:
                      'Extrayez ce tableau en objet métier dédié relié par référence.',
                ),
              );
            } else if (attr.type == BusinessAttributeType.object &&
                attr.estimatedMaxRows == null) {
              issues.add(
                SpecCoherenceIssue(
                  id: 'coh_attr_rows_missing_${obj.id}_${attr.id}',
                  severity: CoherenceSeverity.info,
                  stage: SpecForgeStage.businessObjects,
                  code: 'COH-OBJ-009',
                  title: 'Volumétrie non bornée : $qualified',
                  description:
                      'Précisez estimatedMaxRows (<= 200) sur le tableau imbriqué « ${attr.name} » ou extrayez-le en objet métier séparé s’il dépasse 200 lignes.',
                  targetRef: '${obj.id}.${attr.name}',
                  suggestion: 'Renseignez estimatedMaxRows ou extrayez en objet séparé.',
                ),
              );
            }
          }
          if (attr.schemaConstraints.hasConst &&
              attr.enumValues.isNotEmpty &&
              !attr.enumValues.contains(
                attr.schemaConstraints.constValue?.toString(),
              )) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_attr_const_${obj.id}_${attr.id}',
                severity: CoherenceSeverity.error,
                stage: SpecForgeStage.businessObjects,
                code: 'COH-OBJ-011',
                title: 'Conflit const / enum : $qualified',
                description:
                    'La valeur constante « ${attr.schemaConstraints.constValue} » ne fait pas partie des valeurs énumérées.',
                targetRef: '${obj.id}.${attr.name}',
                suggestion: 'Ajustez const ou enumValues.',
              ),
            );
          }
          if (attr.children.isNotEmpty) {
            checkAttributes(attr.children, qualified);
          }
          if (modelPreferences != null) {
            _checkTechnicalModelingRules(
              issues: issues,
              obj: obj,
              attr: attr,
              qualified: qualified,
              prefs: modelPreferences,
            );
          }
        }
      }

      checkAttributes(obj.attributes, obj.technicalName);

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

    // 3 bis. Contrôles d'Example Mapping (Étape 6)
    if (project.exampleMappings.isNotEmpty) {
      final mappedObjectIds = <String>{};
      final rulesByIdOrCode = <String, BusinessRuleSpec>{
        for (final r in project.businessRules) ...{
          r.id.toLowerCase(): r,
          r.code.toLowerCase(): r,
        },
      };

      for (final story in project.exampleMappings) {
        if (story.targetObjectId.trim().isNotEmpty) {
          final targetObj = objectsByAnyKey[story.targetObjectId.toLowerCase()];
          if (targetObj == null) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_em_missing_obj_${story.id}',
                severity: CoherenceSeverity.error,
                stage: SpecForgeStage.exampleMapping,
                code: 'COH-EM-004',
                title: 'Objet cible inconnu sur ${story.code}',
                description:
                    'Le tableau « ${story.title} » cible l’objet « ${story.targetObjectId} » qui n’existe pas.',
                targetRef: story.id,
                suggestion:
                    'Rattachez ce tableau à un objet métier existant ou recréez l’objet.',
              ),
            );
          } else {
            mappedObjectIds.add(targetObj.id);
          }
        }

        for (final emRule in story.rules) {
          if (emRule.examples.isEmpty) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_em_no_ex_${story.id}_${emRule.id}',
                severity: CoherenceSeverity.info,
                stage: SpecForgeStage.exampleMapping,
                code: 'COH-EM-003',
                title: 'Règle bleue sans exemple vert : ${emRule.title}',
                description:
                    'Dans « ${story.code} — ${story.title} », la règle « ${emRule.title} » ne comporte aucun exemple concret.',
                targetRef: story.id,
                suggestion:
                    'Ajoutez au moins un exemple concret nominal ou aux limites pour vérifier les attributs.',
              ),
            );
          }
          if (emRule.linkedRuleId.trim().isNotEmpty &&
              !rulesByIdOrCode.containsKey(
                emRule.linkedRuleId.trim().toLowerCase(),
              )) {
            issues.add(
              SpecCoherenceIssue(
                id: 'coh_em_missing_rule_${story.id}_${emRule.id}',
                severity: CoherenceSeverity.warning,
                stage: SpecForgeStage.exampleMapping,
                code: 'COH-EM-004',
                title:
                    'Lien RG cassé dans ${story.code} (${emRule.linkedRuleId})',
                description:
                    'La règle bleue « ${emRule.title} » référence « ${emRule.linkedRuleId} », introuvable dans les règles de gestion.',
                targetRef: story.id,
                suggestion:
                    'Promouvez à nouveau cette carte bleue ou corrigez son lien.',
              ),
            );
          }
        }

        final openCount = story.openQuestionCount;
        if (openCount > 0) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_em_open_q_${story.id}',
              severity: CoherenceSeverity.warning,
              stage: SpecForgeStage.exampleMapping,
              code: 'COH-EM-001',
              title:
                  '$openCount question(s) rouge(s) ouverte(s) dans ${story.code}',
              description:
                  'Le tableau « ${story.title} » comporte encore $openCount question(s) non résolue(s) pouvant impacter le modèle métier.',
              targetRef: story.id,
              suggestion:
                  'Tranchez ces questions avec l’Example Mapper ou marquez-les résolues.',
            ),
          );
        }
      }

      for (final obj in project.businessObjects) {
        if (!mappedObjectIds.contains(obj.id)) {
          issues.add(
            SpecCoherenceIssue(
              id: 'coh_em_unmapped_obj_${obj.id}',
              severity: CoherenceSeverity.info,
              stage: SpecForgeStage.exampleMapping,
              code: 'COH-EM-002',
              title: 'Objet sans Example Mapping : ${obj.name}',
              description:
                  'L’objet métier « ${obj.name} » (${obj.technicalName}) n’a pas encore été exploré en Example Mapping.',
              targetRef: obj.id,
              suggestion:
                  'Initialisez un tableau jaune pour vérifier ses cas limites et exemples.',
            ),
          );
        }
      }
    }

    // 4. Contrôles des règles de gestion (Étape 7)
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
              'Passez par l’étape 7 (Rule Architect) pour formaliser validations, calculs et transitions.',
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

  static void _checkTechnicalModelingRules({
    required List<SpecCoherenceIssue> issues,
    required BusinessObjectSpec obj,
    required BusinessAttribute attr,
    required String qualified,
    required BusinessObjectModelPreferences prefs,
  }) {
    final name = attr.name.trim();
    final lower = name.toLowerCase();

    if (prefs.booleanPrefixPolicy == BooleanPrefixPolicy.strictIsHasCan &&
        attr.type == BusinessAttributeType.boolean) {
      final hasPrefix = RegExp(
        r'^(is|has|can|est|a|peut)([A-Z_-]|$)',
      ).hasMatch(name);
      if (!hasPrefix) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_mod_bool_${obj.id}_${attr.id}',
            severity: CoherenceSeverity.info,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-MOD-001',
            title: 'Préfixe booléen recommandé : $qualified',
            description:
                'L’attribut booléen « $name » ne commence pas par un préfixe actif (is*, has*, can*).',
            targetRef: '${obj.id}.$name',
            suggestion:
                'Renommez-le avec un préfixe explicite (ex. is${name.isEmpty ? '' : '${name[0].toUpperCase()}${name.substring(1)}'}).',
          ),
        );
      }
    }

    if (prefs.dateTimeSuffixPolicy == DateTimeSuffixPolicy.strictAtAndDate) {
      if (attr.type == BusinessAttributeType.datetime &&
          lower.endsWith('date') &&
          !lower.endsWith('at')) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_mod_dt_${obj.id}_${attr.id}',
            severity: CoherenceSeverity.info,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-MOD-002',
            title: 'Suffixe *At attendu pour un horodatage : $qualified',
            description:
                'L’attribut « $name » est typé dateTime mais se termine par « Date » au lieu de « At ».',
            targetRef: '${obj.id}.$name',
            suggestion:
                'Utilisez le suffixe *At pour les instants UTC ou passez le type en `date` calendaire.',
          ),
        );
      } else if (attr.type == BusinessAttributeType.date &&
          RegExp(r'(^|_)at$|[a-z0-9]At$').hasMatch(name)) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_mod_date_${obj.id}_${attr.id}',
            severity: CoherenceSeverity.info,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-MOD-003',
            title: 'Suffixe *Date attendu pour une date calendaire : $qualified',
            description:
                'L’attribut « $name » est typé `date` (sans heure) mais porte le suffixe « At ».',
            targetRef: '${obj.id}.$name',
            suggestion:
                'Passez le type en `dateTime` UTC ou renommez avec le suffixe *Date.',
          ),
        );
      }
    }

    if (prefs.enforceIdRefCodeNumberDistinction) {
      final endsWithNumber =
          lower.endsWith('number') || lower.endsWith('_number');
      if (endsWithNumber &&
          (attr.type == BusinessAttributeType.uuid ||
              attr.type == BusinessAttributeType.reference)) {
        issues.add(
          SpecCoherenceIssue(
            id: 'coh_mod_num_${obj.id}_${attr.id}',
            severity: CoherenceSeverity.warning,
            stage: SpecForgeStage.businessObjects,
            code: 'COH-MOD-004',
            title: 'Confusion *Number / *Id sur $qualified',
            description:
                'L’attribut « $name » porte le suffixe *Number mais est typé en ${attr.type.name}.',
            targetRef: '${obj.id}.$name',
            suggestion:
                'Réservez *Id aux clés techniques/références (UUID) et *Number aux numéros séquentiels métier (string).',
          ),
        );
      }
    }
  }
}
