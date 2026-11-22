/// Analyseur déterministe de cohérence Métier↔UX ([UxCoherenceAnalyzer]).
library;

import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_vision.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_navigation_spec.dart';
import '../models/ux/ux_screen_spec.dart';

/// Vérifie de façon déterministe la cohérence référentielle, l'ergonomie structurelle
/// et la couverture Métier↔UX d'un [SpecForgeProject].
abstract final class UxCoherenceAnalyzer {
  /// Exécute tous les contrôles statiques Métier↔UX sur [project] (et optionnellement
  /// contre [companyGlossary]) et retourne la liste immuable des diagnostics triés.
  static List<UxCoherenceIssue> analyze(
    SpecForgeProject project, {
    CompanyGlossary? companyGlossary,
  }) {
    final issues = <UxCoherenceIssue>[];
    final usedIssueIds = <String>{};

    void addIssue({
      required String id,
      required CoherenceSeverity severity,
      required UxForgeStage stage,
      required String code,
      required String title,
      required String description,
      String targetRef = '',
      String suggestion = '',
    }) {
      var candidateId = _sanitizeId(id);
      if (!usedIssueIds.add(candidateId)) {
        var suffix = 2;
        while (!usedIssueIds.add('${candidateId}_$suffix')) {
          suffix++;
        }
        candidateId = '${candidateId}_$suffix';
      }
      issues.add(
        UxCoherenceIssue(
          id: candidateId,
          severity: severity,
          stage: stage,
          code: code,
          title: title,
          description: description,
          targetRef: targetRef,
          suggestion: suggestion,
        ),
      );
    }

    final ux = project.uxSpec;
    final navigation = ux.navigation;

    // 1. COH-UX-JRN-001 : Personas métier non couverts par aucun parcours utilisateur
    for (final persona in project.vision.personas) {
      final covered = ux.journeys.any(
        (j) =>
            j.personaId.trim().isNotEmpty &&
            _matchesPersona(persona, j.personaId),
      );
      if (!covered) {
        addIssue(
          id: 'ux_jrn_uncovered_persona_${persona.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.userJourneys,
          code: 'COH-UX-JRN-001',
          title: 'Persona non couvert par un parcours : ${persona.name}',
          description:
              'Le persona « ${persona.name} » (${persona.id}) n’est rattaché à aucun parcours utilisateur (UxJourneySpec.personaId).',
          targetRef: persona.id,
          suggestion:
              'Ajoutez au moins un parcours utilisateur dédié à « ${persona.name} » dans l’étape Parcours.',
        );
      }
    }

    // 2. COH-UX-JRN-002 : Références cassées dans les parcours utilisateurs
    for (final journey in ux.journeys) {
      final journeyRef = journey.code.trim().isNotEmpty
          ? journey.code.trim()
          : journey.id;

      if (journey.personaId.trim().isNotEmpty &&
          _resolvePersona(project, journey.personaId) == null) {
        addIssue(
          id: 'ux_jrn_unknown_persona_${journey.id}_${journey.personaId}',
          severity: CoherenceSeverity.error,
          stage: UxForgeStage.userJourneys,
          code: 'COH-UX-JRN-002',
          title: 'Persona inconnu sur $journeyRef',
          description:
              'Le parcours « ${journey.name} » référence le persona « ${journey.personaId} » absent du cadrage.',
          targetRef: journeyRef,
          suggestion:
              'Associez un identifiant de persona existant ou déclarez cet acteur dans le cadrage.',
        );
      }

      for (final ucId in journey.useCaseIds) {
        if (ucId.trim().isNotEmpty && _resolveUseCase(project, ucId) == null) {
          addIssue(
            id: 'ux_jrn_unknown_uc_${journey.id}_$ucId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.userJourneys,
            code: 'COH-UX-JRN-002',
            title: 'Cas d’usage inconnu sur $journeyRef',
            description:
                'Le parcours « ${journey.name} » référence le cas d’usage introuvable « $ucId ».',
            targetRef: journeyRef,
            suggestion:
                'Reliez un cas d’usage existant du cahier des charges ou retirez la référence obsolète.',
          );
        }
      }

      for (final reqId in journey.requirementIds) {
        if (reqId.trim().isNotEmpty &&
            _resolveRequirement(project, reqId) == null) {
          addIssue(
            id: 'ux_jrn_unknown_req_${journey.id}_$reqId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.userJourneys,
            code: 'COH-UX-JRN-002',
            title: 'Exigence fonctionnelle inconnue sur $journeyRef',
            description:
                'Le parcours « ${journey.name} » référence l’exigence « $reqId » absente du cahier des charges.',
            targetRef: journeyRef,
            suggestion:
                'Associez un identifiant ou code EXF-xxx existant dans le cahier des charges.',
          );
        }
      }

      for (final step in journey.steps) {
        final routeRef = step.targetRouteId.trim();
        if (routeRef.isNotEmpty && navigation.findRoute(routeRef) == null) {
          addIssue(
            id: 'ux_jrn_unknown_route_${journey.id}_${step.id}_$routeRef',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.userJourneys,
            code: 'COH-UX-JRN-002',
            title: 'Route cible inconnue à l’étape « ${step.title} » ($journeyRef)',
            description:
                'L’étape #${step.order} « ${step.title} » du parcours « ${journey.name} » pointe vers la route « $routeRef » absente de la navigation.',
            targetRef: '${journey.id}.${step.id}',
            suggestion:
                'Déclarez la route « $routeRef » dans l’étape Navigation ou corrigez targetRouteId.',
          );
        }
      }
    }

    // 3. COH-UX-NAV-001 : Navigation vide, homeRouteId invalide ou références de routes cassées
    if (navigation.routes.isEmpty) {
      addIssue(
        id: 'ux_nav_empty_routes',
        severity: CoherenceSeverity.warning,
        stage: UxForgeStage.iaNavigation,
        code: 'COH-UX-NAV-001',
        title: 'Aucune route applicative définie',
        description:
            'L’architecture de navigation ne comporte encore aucune route (UxNavigationSpec.routes est vide).',
        suggestion:
            'Définissez au moins une route d’accueil (ex. « / ») et les vues principales à l’étape Navigation.',
      );
    } else if (navigation.homeRouteId.trim().isNotEmpty &&
        navigation.findRoute(navigation.homeRouteId) == null) {
      addIssue(
        id: 'ux_nav_invalid_home_${navigation.homeRouteId}',
        severity: CoherenceSeverity.error,
        stage: UxForgeStage.iaNavigation,
        code: 'COH-UX-NAV-001',
        title: 'Route d’accueil introuvable : ${navigation.homeRouteId}',
        description:
            'UxNavigationSpec.homeRouteId (« ${navigation.homeRouteId} ») ne correspond à aucune route déclarée.',
        targetRef: navigation.homeRouteId,
        suggestion:
            'Sélectionnez l’identifiant d’une route existante comme route d’accueil.',
      );
    }

    for (final route in navigation.routes) {
      if (route.moduleId.trim().isNotEmpty &&
          _resolveModule(project, route.moduleId) == null) {
        addIssue(
          id: 'ux_nav_unknown_module_${route.id}_${route.moduleId}',
          severity: CoherenceSeverity.error,
          stage: UxForgeStage.iaNavigation,
          code: 'COH-UX-NAV-001',
          title: 'Module inconnu sur la route ${route.path}',
          description:
              'La route « ${route.title} » (${route.id}) référence le module introuvable « ${route.moduleId} ».',
          targetRef: route.id,
          suggestion:
              'Rattachez un module existant du cahier des charges ou laissez moduleId vide.',
        );
      }

      if (route.parentRouteId.trim().isNotEmpty) {
        final parent = navigation.findRoute(route.parentRouteId);
        if (parent == null ||
            parent.id.toLowerCase() == route.id.toLowerCase()) {
          addIssue(
            id: 'ux_nav_unknown_parent_${route.id}_${route.parentRouteId}',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.iaNavigation,
            code: 'COH-UX-NAV-001',
            title: 'Route parente invalide sur ${route.path}',
            description: parent == null
                ? 'La route « ${route.title} » (${route.id}) référence une route parente inconnue « ${route.parentRouteId} ».'
                : 'La route « ${route.title} » (${route.id}) se référence elle-même comme parente.',
            targetRef: route.id,
            suggestion:
                'Pointez vers une route parente existante distincte ou videz parentRouteId.',
          );
        }
      }

      for (final personaId in route.allowedPersonaIds) {
        if (personaId.trim().isNotEmpty &&
            _resolvePersona(project, personaId) == null) {
          addIssue(
            id: 'ux_nav_unknown_persona_${route.id}_$personaId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.iaNavigation,
            code: 'COH-UX-NAV-001',
            title: 'Persona autorisé inconnu sur ${route.path}',
            description:
                'La route « ${route.title} » autorise le persona « $personaId » absent du cadrage.',
            targetRef: route.id,
            suggestion:
                'Utilisez un identifiant de persona défini à l’étape Cadrage.',
          );
        }
      }

      for (final ruleId in route.permissionRuleIds) {
        if (ruleId.trim().isNotEmpty && _resolveRule(project, ruleId) == null) {
          addIssue(
            id: 'ux_nav_unknown_rule_${route.id}_$ruleId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.iaNavigation,
            code: 'COH-UX-NAV-001',
            title: 'Règle d’habilitation inconnue sur ${route.path}',
            description:
                'La route « ${route.title} » référence la règle « $ruleId » absente des règles de gestion.',
            targetRef: route.id,
            suggestion:
                'Associez un code ou identifiant RG-xxx existant de catégorie Habilitation.',
          );
        }
      }

      // 4. COH-UX-NAV-002 : Route sans écran associé
      final hasScreen = ux.screens.any(
        (s) => _screenMatchesRoute(s, route),
      );
      if (!hasScreen) {
        addIssue(
          id: 'ux_nav_orphan_route_${route.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.iaNavigation,
          code: 'COH-UX-NAV-002',
          title: 'Route sans fiche d’écran : ${route.title} (${route.path})',
          description:
              'La route « ${route.title} » (${route.id}) n’est associée à aucun schéma directeur d’écran (UxScreenSpec.routeId).',
          targetRef: route.id,
          suggestion:
              'Créez un UxScreenSpec rattaché à « ${route.id} » dans l’étape Écrans.',
        );
      }
    }

    // 5. COH-UX-SCR-001 & COH-UX-SCR-002 : Références et ergonomie des écrans
    for (final screen in ux.screens) {
      final screenRef = screen.code.trim().isNotEmpty
          ? screen.code.trim()
          : screen.id;

      if (screen.routeId.trim().isNotEmpty &&
          navigation.findRoute(screen.routeId) == null) {
        addIssue(
          id: 'ux_scr_unknown_route_${screen.id}_${screen.routeId}',
          severity: CoherenceSeverity.error,
          stage: UxForgeStage.screenBlueprints,
          code: 'COH-UX-SCR-001',
          title: 'Route introuvable sur $screenRef',
          description:
              'L’écran « ${screen.name} » référence la route « ${screen.routeId} » absente de UxNavigationSpec.',
          targetRef: screenRef,
          suggestion:
              'Associez une route existante ou ajoutez cette route dans l’étape Navigation.',
        );
      }

      BusinessObjectSpec? primaryObject;
      if (screen.primaryObjectId.trim().isNotEmpty) {
        primaryObject = project.findBusinessObject(screen.primaryObjectId);
        if (primaryObject == null) {
          addIssue(
            id: 'ux_scr_unknown_obj_${screen.id}_${screen.primaryObjectId}',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-001',
            title: 'Objet primaire inconnu sur $screenRef',
            description:
                'L’écran « ${screen.name} » référence l’objet primaire « ${screen.primaryObjectId} » absent du modèle métier.',
            targetRef: screenRef,
            suggestion:
                'Sélectionnez un BusinessObjectSpec existant ou créez l’entité manquante.',
          );
        }
      }

      for (final personaId in screen.personaIds) {
        if (personaId.trim().isNotEmpty &&
            _resolvePersona(project, personaId) == null) {
          addIssue(
            id: 'ux_scr_unknown_persona_${screen.id}_$personaId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-001',
            title: 'Persona inconnu sur $screenRef',
            description:
                'L’écran « ${screen.name} » cite le persona « $personaId » absent du cadrage.',
            targetRef: screenRef,
            suggestion: 'Corrigez personaIds avec un acteur existant.',
          );
        }
      }

      for (final ucId in screen.useCaseIds) {
        if (ucId.trim().isNotEmpty && _resolveUseCase(project, ucId) == null) {
          addIssue(
            id: 'ux_scr_unknown_uc_${screen.id}_$ucId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-001',
            title: 'Cas d’usage inconnu sur $screenRef',
            description:
                'L’écran « ${screen.name} » référence le cas d’usage introuvable « $ucId ».',
            targetRef: screenRef,
            suggestion: 'Associez un cas d’usage existant du cahier des charges.',
          );
        }
      }

      for (final reqId in screen.requirementIds) {
        if (reqId.trim().isNotEmpty &&
            _resolveRequirement(project, reqId) == null) {
          addIssue(
            id: 'ux_scr_unknown_req_${screen.id}_$reqId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-001',
            title: 'Exigence inconnue sur $screenRef',
            description:
                'L’écran « ${screen.name} » référence l’exigence « $reqId » absente du cahier des charges.',
            targetRef: screenRef,
            suggestion: 'Associez un identifiant ou code EXF-xxx valide.',
          );
        }
      }

      for (final zone in screen.zones) {
        for (final slot in zone.slots) {
          BusinessObjectSpec? slotObject;
          if (slot.businessObjectId.trim().isNotEmpty) {
            slotObject = project.findBusinessObject(slot.businessObjectId);
            if (slotObject == null) {
              addIssue(
                id: 'ux_scr_slot_unknown_obj_${screen.id}_${slot.id}_${slot.businessObjectId}',
                severity: CoherenceSeverity.error,
                stage: UxForgeStage.screenBlueprints,
                code: 'COH-UX-SCR-001',
                title: 'Objet métier inconnu dans le bloc « ${slot.title} » ($screenRef)',
                description:
                    'Le bloc « ${slot.title} » (zone ${zone.zone.name}) de « ${screen.name} » référence l’objet inconnu « ${slot.businessObjectId} ».',
                targetRef: '${screen.id}.${slot.id}',
                suggestion:
                    'Liez ce slot à un objet métier existant ou corrigez businessObjectId.',
              );
            }
          } else {
            slotObject = primaryObject;
          }

          if (slot.attributeNames.isNotEmpty) {
            if (slotObject != null) {
              for (final attrName in slot.attributeNames) {
                if (attrName.trim().isNotEmpty &&
                    !_objectHasAttributeOrRelation(slotObject, attrName)) {
                  addIssue(
                    id: 'ux_scr_slot_unknown_attr_${screen.id}_${slot.id}_$attrName',
                    severity: CoherenceSeverity.error,
                    stage: UxForgeStage.screenBlueprints,
                    code: 'COH-UX-SCR-001',
                    title: 'Attribut inconnu « $attrName » dans « ${slot.title} » ($screenRef)',
                    description:
                        'Le bloc « ${slot.title} » sur « ${screen.name} » référence l’attribut « $attrName » absent de l’objet « ${slotObject.name} » (${slotObject.technicalName}).',
                    targetRef: '${screen.id}.${slot.id}',
                    suggestion:
                        'Ajoutez l’attribut « $attrName » sur « ${slotObject.technicalName} » ou corrigez attributeNames.',
                  );
                }
              }
            } else if (slot.businessObjectId.trim().isEmpty &&
                screen.primaryObjectId.trim().isEmpty) {
              addIssue(
                id: 'ux_scr_slot_orphan_attrs_${screen.id}_${slot.id}',
                severity: CoherenceSeverity.error,
                stage: UxForgeStage.screenBlueprints,
                code: 'COH-UX-SCR-001',
                title: 'Attributs sans objet métier lié sur « ${slot.title} » ($screenRef)',
                description:
                    'Le bloc « ${slot.title} » liste des attributs (${slot.attributeNames.join(', ')}) sans businessObjectId ni primaryObjectId sur l’écran.',
                targetRef: '${screen.id}.${slot.id}',
                suggestion:
                    'Renseignez businessObjectId sur le slot ou primaryObjectId sur l’écran.',
              );
            }
          }
        }
      }

      for (final action in screen.actions) {
        for (final ruleId in action.businessRuleIds) {
          if (ruleId.trim().isNotEmpty &&
              _resolveRule(project, ruleId) == null) {
            addIssue(
              id: 'ux_scr_act_unknown_rule_${screen.id}_${action.id}_$ruleId',
              severity: CoherenceSeverity.error,
              stage: UxForgeStage.screenBlueprints,
              code: 'COH-UX-SCR-001',
              title: 'Règle de gestion inconnue sur l’action « ${action.label} » ($screenRef)',
              description:
                  'L’action « ${action.label} » de l’écran « ${screen.name} » référence la règle introuvable « $ruleId ».',
              targetRef: '${screen.id}.${action.id}',
              suggestion:
                  'Rattachez un code ou identifiant RG-xxx existant ou formalisez la règle à l’étape 4.',
            );
          }
        }

        if (action.targetRouteId.trim().isNotEmpty &&
            navigation.findRoute(action.targetRouteId) == null) {
          addIssue(
            id: 'ux_scr_act_unknown_route_${screen.id}_${action.id}_${action.targetRouteId}',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-001',
            title: 'Route cible inconnue sur l’action « ${action.label} » ($screenRef)',
            description:
                'L’action « ${action.label} » de l’écran « ${screen.name} » ouvre la route inconnue « ${action.targetRouteId} ».',
            targetRef: '${screen.id}.${action.id}',
            suggestion:
                'Déclarez cette route dans UxNavigationSpec ou corrigez targetRouteId.',
          );
        }
      }

      for (final roRuleId in screen.states.readOnlyRuleIds) {
        if (roRuleId.trim().isNotEmpty &&
            _resolveRule(project, roRuleId) == null) {
          addIssue(
            id: 'ux_scr_state_unknown_rule_${screen.id}_$roRuleId',
            severity: CoherenceSeverity.error,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-001',
            title: 'Règle lecture seule inconnue sur $screenRef',
            description:
                'Les états de l’écran « ${screen.name} » référencent la règle introuvable « $roRuleId ».',
            targetRef: screenRef,
            suggestion: 'Associez un code ou identifiant RG-xxx existant.',
          );
        }
      }

      // COH-UX-SCR-002 : Ergonomie spatiale, hiérarchie d'actions et état vide
      if (screen.pattern == UxScreenPattern.masterDetail) {
        final west = screen.zoneFor(UxLayoutZoneName.west);
        final center = screen.zoneFor(UxLayoutZoneName.center);
        final hasEnabledWest = west != null && west.enabled;
        final hasEnabledCenter = center != null && center.enabled;
        if (!hasEnabledWest || !hasEnabledCenter) {
          final missing = <String>[
            if (!hasEnabledWest) 'west',
            if (!hasEnabledCenter) 'center',
          ].join(' et ');
          addIssue(
            id: 'ux_scr_master_detail_zones_${screen.id}',
            severity: CoherenceSeverity.warning,
            stage: UxForgeStage.screenBlueprints,
            code: 'COH-UX-SCR-002',
            title: 'Zones Maître/Détail incomplètes sur $screenRef',
            description:
                'L’écran Maître/Détail « ${screen.name} » doit activer les zones west et center (manquant : $missing).',
            targetRef: screenRef,
            suggestion:
                'Activez une zone west fixe (ex. 320 px) pour la liste maître et une zone center pour la fiche détail.',
          );
        }
      }

      final primaryActions = screen.actions
          .where((a) => a.hierarchy == UxActionHierarchy.primary)
          .toList();
      if (primaryActions.length > 1) {
        addIssue(
          id: 'ux_scr_multiple_primary_actions_${screen.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.screenBlueprints,
          code: 'COH-UX-SCR-002',
          title: 'Plusieurs actions primaires sur $screenRef',
          description:
              'L’écran « ${screen.name} » expose ${primaryActions.length} actions de hiérarchie primary (${primaryActions.map((a) => '« ${a.label} »').join(', ')}), alors que le Design System limite à un seul CTA primaire par vue.',
          targetRef: screenRef,
          suggestion:
              'Conservez une seule action primary (filled) et reclassez les autres en secondary, destructive ou inline.',
        );
      }

      if (screen.states.emptyStateTitle.trim().isEmpty) {
        addIssue(
          id: 'ux_scr_empty_state_missing_${screen.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.screenBlueprints,
          code: 'COH-UX-SCR-002',
          title: 'État vide non renseigné sur $screenRef',
          description:
              'L’écran « ${screen.name} » ne définit pas de message d’état vide (states.emptyStateTitle).',
          targetRef: screenRef,
          suggestion:
              'Renseignez un emptyStateTitle explicite en français (et un emptyStateCta si une création est possible).',
        );
      }
    }

    // 6. COH-UX-COV-001 : Couverture des exigences Must, cas d'usage et agrégats racines
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (req.priority != RequirementPriority.must) continue;
      final coveredByJourney = ux.journeys.any(
        (j) => j.requirementIds.any((ref) => _matchesRequirement(req, ref)),
      );
      final coveredByScreen = ux.screens.any(
        (s) => s.requirementIds.any((ref) => _matchesRequirement(req, ref)),
      );
      if (!coveredByJourney && !coveredByScreen) {
        final reqRef = req.code.trim().isNotEmpty ? req.code.trim() : req.id;
        addIssue(
          id: 'ux_cov_must_req_${req.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.uxReviewExport,
          code: 'COH-UX-COV-001',
          title: 'Exigence Must non couverte en UX : $reqRef',
          description:
              'L’exigence indispensable « ${req.title} » ($reqRef) n’est rattachée à aucun parcours ni écran UX.',
          targetRef: reqRef,
          suggestion:
              'Associez $reqRef à au moins un parcours utilisateur ou un écran dans le volet UX.',
        );
      }
    }

    for (final uc in project.cahierDesCharges.useCases) {
      final coveredByJourney = ux.journeys.any(
        (j) => j.useCaseIds.any((ref) => _matchesUseCase(uc, ref)),
      );
      final coveredByScreen = ux.screens.any(
        (s) => s.useCaseIds.any((ref) => _matchesUseCase(uc, ref)),
      );
      if (!coveredByJourney && !coveredByScreen) {
        addIssue(
          id: 'ux_cov_use_case_${uc.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.uxReviewExport,
          code: 'COH-UX-COV-001',
          title: 'Cas d’usage non couvert en UX : ${uc.title}',
          description:
              'Le cas d’usage « ${uc.title} » (${uc.id}) n’est référencé par aucun parcours ni écran UX.',
          targetRef: uc.id,
          suggestion:
              'Intégrez « ${uc.id} » dans un parcours utilisateur et/ou dans un écran correspondant.',
        );
      }
    }

    for (final obj in project.businessObjects) {
      if (!obj.aggregateRoot) continue;
      final coveredByScreen = ux.screens.any((s) {
        if (s.primaryObjectId.trim().isNotEmpty &&
            _matchesBusinessObject(obj, s.primaryObjectId)) {
          return true;
        }
        for (final zone in s.zones) {
          for (final slot in zone.slots) {
            if (slot.businessObjectId.trim().isNotEmpty &&
                _matchesBusinessObject(obj, slot.businessObjectId)) {
              return true;
            }
          }
        }
        return false;
      });
      if (!coveredByScreen) {
        addIssue(
          id: 'ux_cov_aggregate_root_${obj.id}',
          severity: CoherenceSeverity.warning,
          stage: UxForgeStage.uxReviewExport,
          code: 'COH-UX-COV-001',
          title: 'Agrégat racine absent des écrans UX : ${obj.name}',
          description:
              'L’agrégat racine « ${obj.name} » (${obj.technicalName}) n’est référencé par aucun écran UX (primaryObjectId ou slot.businessObjectId).',
          targetRef: obj.id,
          suggestion:
              'Créez un écran ou un bloc UX lié à « ${obj.technicalName} » pour exposer cet agrégat.',
        );
      }
    }

    // 7. COH-UX-LEX-001 : Termes proscrits ou dépréciés du glossaire d'entreprise dans les libellés UX
    if (companyGlossary != null && companyGlossary.terms.isNotEmpty) {
      final rules = _buildGlossaryRules(companyGlossary);
      if (rules.isNotEmpty) {
        void checkText({
          required String idPrefix,
          required UxForgeStage stage,
          required String targetRef,
          required String contextLabel,
          required String text,
        }) {
          final trimmed = text.trim();
          if (trimmed.isEmpty) return;
          for (final rule in rules) {
            if (rule.pattern.hasMatch(trimmed)) {
              addIssue(
                id: '${idPrefix}_${rule.matchedTerm}',
                severity: CoherenceSeverity.warning,
                stage: stage,
                code: 'COH-UX-LEX-001',
                title: rule.isDeprecated
                    ? 'Terme déprécié « ${rule.matchedTerm} » dans $contextLabel'
                    : 'Terme proscrit « ${rule.matchedTerm} » dans $contextLabel',
                description: rule.isDeprecated
                    ? '$contextLabel (« $trimmed ») emploie le terme d’entreprise déprécié « ${rule.matchedTerm} ».'
                    : '$contextLabel (« $trimmed ») emploie le terme proscrit « ${rule.matchedTerm} » au lieu du terme officiel « ${rule.canonicalTerm.term} ».',
                targetRef: targetRef,
                suggestion: rule.isDeprecated
                    ? 'Remplacez « ${rule.matchedTerm} » par un terme validé du glossaire d’entreprise.'
                    : 'Utilisez le terme canonique « ${rule.canonicalTerm.term} » dans les intitulés UX.',
              );
            }
          }
        }

        for (final journey in ux.journeys) {
          final ref = journey.code.trim().isNotEmpty
              ? journey.code.trim()
              : journey.id;
          checkText(
            idPrefix: 'ux_lex_jrn_${journey.id}',
            stage: UxForgeStage.userJourneys,
            targetRef: ref,
            contextLabel: 'Le parcours $ref',
            text: journey.name,
          );
        }

        for (final route in navigation.routes) {
          checkText(
            idPrefix: 'ux_lex_route_${route.id}',
            stage: UxForgeStage.iaNavigation,
            targetRef: route.id,
            contextLabel: 'La route ${route.path}',
            text: route.title,
          );
        }

        for (final screen in ux.screens) {
          final ref = screen.code.trim().isNotEmpty
              ? screen.code.trim()
              : screen.id;
          checkText(
            idPrefix: 'ux_lex_scr_${screen.id}',
            stage: UxForgeStage.screenBlueprints,
            targetRef: ref,
            contextLabel: 'L’écran $ref',
            text: screen.name,
          );
          for (final action in screen.actions) {
            checkText(
              idPrefix: 'ux_lex_act_${screen.id}_${action.id}',
              stage: UxForgeStage.screenBlueprints,
              targetRef: '${screen.id}.${action.id}',
              contextLabel: 'L’action « ${action.label} » ($ref)',
              text: action.label,
            );
          }
        }
      }
    }

    issues.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      final byStage = a.stage.index.compareTo(b.stage.index);
      if (byStage != 0) return byStage;
      final byCode = a.code.compareTo(b.code);
      if (byCode != 0) return byCode;
      return a.id.compareTo(b.id);
    });
    return List<UxCoherenceIssue>.unmodifiable(issues);
  }

  static SpecPersona? _resolvePersona(SpecForgeProject project, String ref) {
    for (final persona in project.vision.personas) {
      if (_matchesPersona(persona, ref)) return persona;
    }
    return null;
  }

  static bool _matchesPersona(SpecPersona persona, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return persona.id.toLowerCase() == needle ||
        persona.name.toLowerCase() == needle;
  }

  static UseCaseSpec? _resolveUseCase(SpecForgeProject project, String ref) {
    for (final uc in project.cahierDesCharges.useCases) {
      if (_matchesUseCase(uc, ref)) return uc;
    }
    return null;
  }

  static bool _matchesUseCase(UseCaseSpec uc, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return uc.id.toLowerCase() == needle || uc.title.toLowerCase() == needle;
  }

  static FunctionalRequirement? _resolveRequirement(
    SpecForgeProject project,
    String ref,
  ) {
    for (final req in project.cahierDesCharges.functionalRequirements) {
      if (_matchesRequirement(req, ref)) return req;
    }
    return null;
  }

  static bool _matchesRequirement(FunctionalRequirement req, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return req.id.toLowerCase() == needle ||
        (req.code.trim().isNotEmpty && req.code.trim().toLowerCase() == needle);
  }

  static SpecModule? _resolveModule(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final module in project.cahierDesCharges.modules) {
      if (module.id.toLowerCase() == needle ||
          module.name.toLowerCase() == needle) {
        return module;
      }
    }
    return null;
  }

  static BusinessRuleSpec? _resolveRule(SpecForgeProject project, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final rule in project.businessRules) {
      if (rule.id.toLowerCase() == needle ||
          (rule.code.trim().isNotEmpty &&
              rule.code.trim().toLowerCase() == needle)) {
        return rule;
      }
    }
    return null;
  }

  static bool _matchesBusinessObject(BusinessObjectSpec obj, String ref) {
    final needle = ref.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return obj.id.toLowerCase() == needle ||
        obj.technicalName.toLowerCase() == needle ||
        obj.name.toLowerCase() == needle;
  }

  static bool _screenMatchesRoute(UxScreenSpec screen, UxRouteNode route) {
    final raw = screen.routeId.trim();
    if (raw.isEmpty) return false;
    final lower = raw.toLowerCase();
    if (route.id.toLowerCase() == lower) return true;
    final normalized = UxRouteNode.normalizePath(raw).toLowerCase();
    return route.path.toLowerCase() == lower ||
        route.path.toLowerCase() == normalized;
  }

  static bool _objectHasAttributeOrRelation(
    BusinessObjectSpec obj,
    String rawAttrPath,
  ) {
    final cleaned = rawAttrPath
        .trim()
        .replaceAll('[?]', '')
        .replaceAll('[]', '');
    if (cleaned.isEmpty) return false;
    final segments = cleaned
        .split('.')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return false;

    final firstLower = segments.first.toLowerCase();
    if (segments.length == 1 &&
        obj.relations.any((r) => r.name.toLowerCase() == firstLower)) {
      return true;
    }

    List<BusinessAttribute> currentLevel = obj.attributes;
    for (var i = 0; i < segments.length; i++) {
      final segLower = segments[i].toLowerCase();
      BusinessAttribute? match;
      for (final attr in currentLevel) {
        if (attr.name.toLowerCase() == segLower ||
            attr.id.toLowerCase() == segLower) {
          match = attr;
          break;
        }
      }
      if (match == null) return false;
      if (i < segments.length - 1) {
        currentLevel = match.children;
      }
    }
    return true;
  }

  static List<_GlossaryLexRule> _buildGlossaryRules(CompanyGlossary glossary) {
    final rules = <_GlossaryLexRule>[];
    final seenKeys = <String>{};

    void register({
      required String rawPhrase,
      required CompanyGlossaryTerm canonical,
      required bool isDeprecated,
    }) {
      final trimmed = rawPhrase.trim();
      if (trimmed.isEmpty) return;
      final normKey = '${isDeprecated ? 'dep' : 'forb'}:${trimmed.toLowerCase()}';
      if (!seenKeys.add(normKey)) return;
      final tokens = trimmed
          .split(RegExp(r'\s+'))
          .map(RegExp.escape)
          .join(r'\s+');
      final pattern = RegExp(
        '(?<![A-Za-zÀ-ÖØ-öø-ÿ0-9])$tokens(?:s|x)?(?![A-Za-zÀ-ÖØ-öø-ÿ0-9])',
        caseSensitive: false,
      );
      rules.add(
        _GlossaryLexRule(
          matchedTerm: trimmed,
          canonicalTerm: canonical,
          isDeprecated: isDeprecated,
          pattern: pattern,
        ),
      );
    }

    for (final term in glossary.terms) {
      if (term.status == CompanyGlossaryStatus.deprecated) {
        register(rawPhrase: term.term, canonical: term, isDeprecated: true);
      }
      for (final forbidden in term.forbiddenTerms) {
        register(
          rawPhrase: forbidden,
          canonical: term,
          isDeprecated: false,
        );
      }
    }
    return rules;
  }

  static String _sanitizeId(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'ux_coh_issue' : cleaned;
  }
}

class _GlossaryLexRule {
  const _GlossaryLexRule({
    required this.matchedTerm,
    required this.canonicalTerm,
    required this.isDeprecated,
    required this.pattern,
  });

  final String matchedTerm;
  final CompanyGlossaryTerm canonicalTerm;
  final bool isDeprecated;
  final RegExp pattern;
}
