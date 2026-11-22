/// Tests unitaires de l'analyseur de cohérence UX ([UxCoherenceAnalyzer]) et des exportateurs UX / SuperDesigner ([UxMarkdownExporter], [UxDesignMdExporter], [SpecSuperDesignerExporter]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Color, ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  CompanyGlossary buildSampleGlossary() => CompanyGlossary(
    terms: [
      CompanyGlossaryTerm(
        id: 'cg_commande',
        term: 'Commande',
        definition: 'Ordre d’achat B2B validé par un acheteur habilité.',
        synonyms: const ['BC'],
        forbiddenTerms: const ['Devis papier', 'Bon volant'],
        domain: 'Ventes B2B',
        status: CompanyGlossaryStatus.approved,
      ),
      CompanyGlossaryTerm(
        id: 'cg_telecopie',
        term: 'Télécopie client',
        definition: 'Ancien canal fax abandonné.',
        domain: 'Ventes B2B',
        status: CompanyGlossaryStatus.deprecated,
      ),
    ],
    conventions: const ['Montants exprimés en EUR HT'],
  );

  SpecForgeProject buildCoherentUxProject() {
    final base = SpecForgeProject.fromIdea(
      idea: 'Portail de pilotage des commandes B2B',
      name: 'B2B Order Studio',
    );
    return base.copyWith(
      lexicon: SpecLexicon(
        terms: [
          LexiconTerm(
            id: 't_cmd',
            term: 'Commande',
            definition: 'Ordre d’achat B2B validé par un acheteur habilité.',
            synonyms: const ['BC'],
            domain: 'Ventes B2B',
          ),
        ],
      ),
      vision: base.vision.copyWith(
        problemStatement: 'Commandes B2B dispersées par email sans suivi.',
        valueProposition: 'Cockpit B2B unifié de saisie, validation et édition PDF des commandes.',
        objectives: const ['Zéro ressaisie manuelle'],
        personas: [
          SpecPersona(
            id: 'p_acheteur',
            name: 'Acheteur B2B',
            role: 'Saisit, contrôle et valide les commandes fournisseurs',
            goals: const ['Valider une commande en moins de 3 clics'],
          ),
        ],
      ),
      cahierDesCharges: SpecCahierDesCharges(
        modules: const [
          SpecModule(
            id: 'mod_cmd',
            name: 'Commandes',
            description: 'Cycle complet des commandes B2B',
          ),
        ],
        functionalRequirements: [
          FunctionalRequirement(
            id: 'req_1',
            code: 'EXF-001',
            title: 'Création et suivi de commande',
            moduleId: 'mod_cmd',
            priority: RequirementPriority.must,
            actorIds: const ['p_acheteur'],
            acceptanceCriteria: const ['Le statut est affiché en temps réel'],
          ),
        ],
        useCases: [
          UseCaseSpec(
            id: 'uc_1',
            title: 'Passer et valider une commande',
            actorId: 'p_acheteur',
            mainFlow: const [
              'Consulter le portefeuille de commandes',
              'Ouvrir la modale de création ou valider la commande sélectionnée',
            ],
          ),
        ],
      ),
      businessObjects: [
        BusinessObjectSpec(
          id: 'obj_commande',
          name: 'Commande',
          technicalName: 'Commande',
          description: 'Commande client B2B',
          aggregateRoot: true,
          attributes: [
            BusinessAttribute(
              id: 'a_ref',
              name: 'reference',
              type: BusinessAttributeType.string,
              required: true,
            ),
            BusinessAttribute(
              id: 'a_montant',
              name: 'montantHt',
              type: BusinessAttributeType.number,
              required: true,
            ),
            BusinessAttribute(
              id: 'a_urgent',
              name: 'estUrgente',
              type: BusinessAttributeType.boolean,
            ),
            BusinessAttribute(
              id: 'a_statut',
              name: 'statut',
              type: BusinessAttributeType.enumeration,
              required: true,
              enumValues: const ['brouillon', 'validee'],
            ),
          ],
          relations: const [
            BusinessRelation(
              id: 'rel_lignes',
              name: 'lignes',
              targetObjectId: 'obj_ligne_commande',
              cardinality: BusinessRelationCardinality.oneToMany,
            ),
          ],
          lifecycleStates: const [
            LifecycleState(name: 'brouillon', isInitial: true),
            LifecycleState(name: 'validee', isTerminal: true),
          ],
          lifecycleTransitions: const [
            LifecycleTransition(
              id: 'tr_valider',
              fromState: 'brouillon',
              toState: 'validee',
              trigger: 'Validation acheteur',
            ),
          ],
        ),
        BusinessObjectSpec(
          id: 'obj_ligne_commande',
          name: 'Ligne de commande',
          technicalName: 'LigneCommande',
          description: 'Poste unitaire rattaché à une commande',
          aggregateRoot: false,
          attributes: [
            BusinessAttribute(
              id: 'a_des',
              name: 'designation',
              type: BusinessAttributeType.string,
              required: true,
            ),
            BusinessAttribute(
              id: 'a_qte',
              name: 'quantite',
              type: BusinessAttributeType.integer,
              required: true,
            ),
          ],
        ),
      ],
      businessRules: [
        BusinessRuleSpec(
          id: 'rg_1',
          code: 'RG-001',
          title: 'Validation d’une commande brouillon',
          category: BusinessRuleCategory.stateTransition,
          targetObjectIds: const ['obj_commande'],
          trigger: 'Clic sur Valider',
          condition: 'statut == brouillon',
          effect: 'statut = validee',
        ),
        BusinessRuleSpec(
          id: 'rg_2',
          code: 'RG-002',
          title: 'Habilitation acheteur et verrouillage après validation',
          category: BusinessRuleCategory.permission,
          targetObjectIds: const ['obj_commande'],
          condition: 'role == p_acheteur',
          effect: 'Autoriser accès et figer en lecture seule si validee',
        ),
      ],
      uxSpec: UxForgeSpec(
        currentStage: UxForgeStage.uxReviewExport,
        journeys: [
          UxJourneySpec(
            id: 'jrn_1',
            code: 'JRN-001',
            name: 'Validation rapide d’une commande',
            personaId: 'p_acheteur',
            useCaseIds: const ['uc_1'],
            requirementIds: const ['EXF-001'],
            channel: UxTargetChannel.desktop,
            trigger: 'Réception d’un besoin d’approvisionnement',
            goal: 'Créer ou valider une commande sans ressaisie',
            steps: const [
              UxJourneyStep(
                id: 'step_1',
                order: 1,
                title: 'Consultation du portefeuille',
                actorAction: 'Sélectionne une commande dans la liste maître',
                systemResponse: 'Affiche la fiche détail et les lignes liées',
                targetRouteId: 'route_commandes',
                painPointResolved: 'Suppression des échanges email dispersés',
              ),
              UxJourneyStep(
                id: 'step_2',
                order: 2,
                title: 'Création rapide en modale',
                actorAction: 'Clique sur Nouvelle commande',
                systemResponse: 'Ouvre le formulaire modal pré-rempli',
                targetRouteId: 'route_nouvelle_commande',
                branchCondition: 'Si la commande n’existe pas encore',
              ),
            ],
            successCriteria: const ['Validation complète en moins de 3 clics'],
          ),
        ],
        navigation: UxNavigationSpec(
          shellPattern: UxShellPattern.navigationRail,
          hasAppBar: true,
          hasBreadcrumbs: true,
          hasGlobalSearch: true,
          homeRouteId: 'route_commandes',
          visualTheme: const UxVisualThemeSeed(
            accentHex: '#0EA5E9',
            themeMode: 'dark',
            surfaceSystem: 'liquidGlass',
            fontFamily: 'Plus Jakarta Sans',
            density: UxDensityProfile.comfortable,
            cardRadius: 18.0,
            uxVoiceGuidelines:
                'Micro-copie concise, active et orientée métier.',
          ),
          routes: [
            UxRouteNode(
              id: 'route_commandes',
              path: '/commandes',
              title: 'Commandes B2B',
              iconName: 'receipt_long_outlined',
              pageType: EditorPageType.standard,
              moduleId: 'mod_cmd',
              allowedPersonaIds: const ['p_acheteur'],
              permissionRuleIds: const ['RG-002'],
              showInPrimaryNav: true,
            ),
            UxRouteNode(
              id: 'route_nouvelle_commande',
              path: '/commandes/nouvelle',
              title: 'Nouvelle commande',
              iconName: 'add_circle_outline',
              pageType: EditorPageType.dialog,
              moduleId: 'mod_cmd',
              parentRouteId: 'route_commandes',
              allowedPersonaIds: const ['p_acheteur'],
              showInPrimaryNav: false,
            ),
            UxRouteNode(
              id: 'route_bon_pdf',
              path: '/commandes/bon-pdf',
              title: 'Bon de commande A4',
              iconName: 'picture_as_pdf_outlined',
              pageType: EditorPageType.a4Document,
              moduleId: 'mod_cmd',
              parentRouteId: 'route_commandes',
              allowedPersonaIds: const ['p_acheteur'],
              showInPrimaryNav: true,
            ),
          ],
        ),
        screens: [
          UxScreenSpec(
            id: 'scr_commandes',
            code: 'SCR-001',
            name: 'Portefeuille des commandes',
            routeId: 'route_commandes',
            pattern: UxScreenPattern.masterDetail,
            purpose: 'Consulter, filtrer et piloter les commandes B2B.',
            personaIds: const ['p_acheteur'],
            useCaseIds: const ['uc_1'],
            requirementIds: const ['EXF-001'],
            primaryObjectId: 'obj_commande',
            zones: [
              UxScreenZoneSpec(
                zone: UxLayoutZoneName.west,
                sizePx: 320,
                slots: [
                  UxZoneWidgetSlot(
                    id: 'slot_search',
                    title: 'Recherche rapide',
                    kind: UxWidgetKind.searchFilterBar,
                  ),
                  UxZoneWidgetSlot(
                    id: 'slot_master_list',
                    title: 'Liste des commandes',
                    kind: UxWidgetKind.masterList,
                    businessObjectId: 'obj_commande',
                    attributeNames: const ['reference', 'statut'],
                  ),
                ],
              ),
              UxScreenZoneSpec(
                zone: UxLayoutZoneName.center,
                slots: [
                  UxZoneWidgetSlot(
                    id: 'slot_detail',
                    title: 'Détail commande',
                    kind: UxWidgetKind.detailCard,
                    businessObjectId: 'obj_commande',
                    attributeNames: const ['reference', 'montantHt', 'statut'],
                    summary: 'Informations principales de la commande',
                  ),
                  UxZoneWidgetSlot(
                    id: 'slot_lignes',
                    title: 'Postes de commande',
                    kind: UxWidgetKind.dataTable,
                    businessObjectId: 'obj_ligne_commande',
                    attributeNames: const ['designation', 'quantite'],
                  ),
                ],
              ),
            ],
            actions: [
              UxScreenAction(
                id: 'act_new',
                label: 'Nouvelle commande',
                hierarchy: UxActionHierarchy.primary,
                businessRuleIds: const ['RG-001'],
                targetRouteId: 'route_nouvelle_commande',
              ),
              UxScreenAction(
                id: 'act_pdf',
                label: 'Aperçu PDF A4',
                hierarchy: UxActionHierarchy.secondary,
                targetRouteId: 'route_bon_pdf',
              ),
              UxScreenAction(
                id: 'act_cancel',
                label: 'Supprimer le brouillon',
                hierarchy: UxActionHierarchy.destructive,
                businessRuleIds: const ['RG-002'],
                confirmationMessage:
                    'Confirmer la suppression définitive de ce brouillon ?',
              ),
            ],
            states: UxScreenStatesSpec(
              emptyStateTitle: 'Aucune commande B2B enregistrée',
              emptyStateCta: 'Créer la première commande',
              loadingPattern: 'skeleton',
              errorHandling: 'Bandeau d’alerte avec action Réessayer',
            ),
          ),
          UxScreenSpec(
            id: 'scr_nouvelle_commande',
            code: 'SCR-002',
            name: 'Saisie d’une commande',
            routeId: 'route_nouvelle_commande',
            pattern: UxScreenPattern.form,
            purpose: 'Créer rapidement une nouvelle commande validable.',
            personaIds: const ['p_acheteur'],
            primaryObjectId: 'obj_commande',
            zones: [
              UxScreenZoneSpec(
                zone: UxLayoutZoneName.center,
                scrollable: true,
                slots: [
                  UxZoneWidgetSlot(
                    id: 'slot_form_cmd',
                    title: 'Informations de commande',
                    kind: UxWidgetKind.formSection,
                    businessObjectId: 'obj_commande',
                    attributeNames: const [
                      'reference',
                      'montantHt',
                      'estUrgente',
                      'statut',
                    ],
                  ),
                ],
              ),
            ],
            actions: [
              UxScreenAction(
                id: 'act_save_cmd',
                label: 'Valider la commande',
                hierarchy: UxActionHierarchy.primary,
                businessRuleIds: const ['RG-001'],
                targetRouteId: 'route_commandes',
              ),
            ],
            states: UxScreenStatesSpec(
              emptyStateTitle: 'Complétez les champs obligatoires',
              readOnlyRuleIds: const ['RG-002'],
            ),
          ),
          UxScreenSpec(
            id: 'scr_bon_pdf',
            code: 'SCR-003',
            name: 'Édition A4 du bon de commande',
            routeId: 'route_bon_pdf',
            pattern: UxScreenPattern.documentA4,
            purpose: 'Prévisualiser et exporter le bon de commande officiel.',
            personaIds: const ['p_acheteur'],
            primaryObjectId: 'obj_commande',
            zones: UxScreenSpec.defaultZonesForPattern(
              UxScreenPattern.documentA4,
            ),
            states: UxScreenStatesSpec(
              emptyStateTitle: 'Aucune commande sélectionnée pour impression',
            ),
          ),
        ],
      ),
    );
  }

  group('UxCoherenceAnalyzer.analyze', () {
    test('retourne zéro erreur et zéro avertissement sur un projet Métier + UX cohérent', () {
      final project = buildCoherentUxProject();
      final glossary = buildSampleGlossary();

      expect(project.validate, returnsNormally);
      expect(SpecForgeProject.fromJson(project.toJson()), equals(project));
      expect(
        SpecCoherenceAnalyzer.analyze(project, companyGlossary: glossary),
        isEmpty,
      );
      expect(
        UxCoherenceAnalyzer.analyze(project, companyGlossary: glossary),
        isEmpty,
      );
    });

    test('détecte les personas métier non couverts (COH-UX-JRN-001)', () {
      final base = buildCoherentUxProject();
      final withUncoveredPersona = base.copyWith(
        vision: base.vision.copyWith(
          personas: [
            ...base.vision.personas,
            SpecPersona(
              id: 'p_auditeur',
              name: 'Auditeur financier',
              role: 'Contrôle la conformité comptable',
            ),
          ],
        ),
      );

      final issues = UxCoherenceAnalyzer.analyze(withUncoveredPersona);
      expect(issues, hasLength(1));
      final issue = issues.single;
      expect(issue.code, 'COH-UX-JRN-001');
      expect(issue.severity, CoherenceSeverity.warning);
      expect(issue.stage, UxForgeStage.userJourneys);
      expect(issue.targetRef, 'p_auditeur');
    });

    test('détecte les références cassées dans les parcours, routes et écrans (COH-UX-JRN-002, COH-UX-NAV-001, COH-UX-SCR-001)', () {
      final base = buildCoherentUxProject();
      final broken = base.copyWith(
        uxSpec: base.uxSpec.copyWith(
          journeys: [
            base.uxSpec.journeys.single.copyWith(
              personaId: 'p_fantome',
              useCaseIds: const ['uc_inconnu'],
              requirementIds: const ['EXF-999'],
              steps: const [
                UxJourneyStep(
                  id: 'step_bad_route',
                  order: 1,
                  title: 'Navigation introuvable',
                  targetRouteId: 'route_absente',
                ),
              ],
            ),
            // Conserve la couverture de p_acheteur, uc_1 et EXF-001 pour isoler les erreurs de référence.
            base.uxSpec.journeys.single.copyWith(
              id: 'jrn_valid_cov',
              code: 'JRN-002',
            ),
          ],
          navigation: base.uxSpec.navigation.copyWith(
            homeRouteId: 'route_accueil_fantome',
            routes: [
              base.uxSpec.navigation.routes.first.copyWith(
                moduleId: 'mod_inconnu',
                parentRouteId: 'route_commandes',
                allowedPersonaIds: const ['p_inconnu'],
                permissionRuleIds: const ['RG-999'],
              ),
              ...base.uxSpec.navigation.routes.skip(1),
            ],
          ),
          screens: [
            ...base.uxSpec.screens,
            UxScreenSpec(
              id: 'scr_broken',
              code: 'SCR-099',
              name: 'Écran cassé',
              routeId: 'route_inexistante',
              pattern: UxScreenPattern.form,
              primaryObjectId: 'obj_inconnu',
              personaIds: const ['p_inconnu'],
              useCaseIds: const ['uc_inconnu'],
              requirementIds: const ['EXF-404'],
              zones: [
                UxScreenZoneSpec(
                  zone: UxLayoutZoneName.center,
                  slots: [
                    UxZoneWidgetSlot(
                      id: 'slot_bad_obj',
                      title: 'Bloc objet inconnu',
                      kind: UxWidgetKind.detailCard,
                      businessObjectId: 'obj_fantome',
                    ),
                    UxZoneWidgetSlot(
                      id: 'slot_bad_attr',
                      title: 'Bloc attribut inconnu',
                      kind: UxWidgetKind.detailCard,
                      businessObjectId: 'obj_commande',
                      attributeNames: const ['champInexistant'],
                    ),
                  ],
                ),
              ],
              actions: [
                UxScreenAction(
                  id: 'act_bad',
                  label: 'Action invalide',
                  businessRuleIds: const ['RG-404'],
                  targetRouteId: 'route_introuvable',
                ),
              ],
              states: UxScreenStatesSpec(
                emptyStateTitle: 'Vide',
                readOnlyRuleIds: const ['RG-405'],
              ),
            ),
            UxScreenSpec(
              id: 'scr_orphan_attrs',
              code: 'SCR-100',
              name: 'Écran sans objet lié',
              routeId: 'route_commandes',
              pattern: UxScreenPattern.custom,
              zones: [
                UxScreenZoneSpec(
                  zone: UxLayoutZoneName.center,
                  slots: [
                    UxZoneWidgetSlot(
                      id: 'slot_orphan_attr',
                      title: 'Attributs orphelins',
                      kind: UxWidgetKind.detailCard,
                      attributeNames: const ['reference'],
                    ),
                  ],
                ),
              ],
              states: UxScreenStatesSpec(emptyStateTitle: 'État vide OK'),
            ),
          ],
        ),
      );

      final issues = UxCoherenceAnalyzer.analyze(broken);
      final jrnIssues = issues
          .where((i) => i.code == 'COH-UX-JRN-002')
          .toList();
      final navIssues = issues
          .where((i) => i.code == 'COH-UX-NAV-001')
          .toList();
      final scrIssues = issues
          .where((i) => i.code == 'COH-UX-SCR-001')
          .toList();

      // 4 erreurs JRN-002 : persona, cas d'usage, exigence, route cible d'étape.
      expect(jrnIssues, hasLength(4));
      expect(
        jrnIssues.every((i) => i.severity == CoherenceSeverity.error),
        isTrue,
      );

      // 5 erreurs NAV-001 : homeRouteId, moduleId, parentRouteId auto-référent, persona, RG.
      expect(navIssues, hasLength(5));
      expect(
        navIssues.every((i) => i.severity == CoherenceSeverity.error),
        isTrue,
      );

      // 11 erreurs SCR-001 : routeId, primaryObjectId, personaId, useCaseId, reqId,
      // slot.businessObjectId, slot.attributeNames inconnu, action.RG, action.route,
      // states.readOnlyRuleIds, et attributs sans objet lié.
      expect(scrIssues, hasLength(11));
      expect(
        scrIssues.every((i) => i.severity == CoherenceSeverity.error),
        isTrue,
      );

      // Vérifie aussi l'avertissement COH-UX-NAV-001 lorsque la liste des routes est vide.
      final emptyNavProject = base.copyWith(
        uxSpec: base.uxSpec.copyWith(navigation: UxNavigationSpec.empty),
      );
      final emptyNavIssues = UxCoherenceAnalyzer.analyze(emptyNavProject);
      expect(
        emptyNavIssues.any(
          (i) =>
              i.code == 'COH-UX-NAV-001' &&
              i.severity == CoherenceSeverity.warning,
        ),
        isTrue,
      );
    });

    test('détecte les routes sans écran (COH-UX-NAV-002) et les défauts ergonomiques masterDetail / actions primaires / état vide (COH-UX-SCR-002)', () {
      final base = buildCoherentUxProject();
      final project = base.copyWith(
        uxSpec: base.uxSpec.copyWith(
          navigation: base.uxSpec.navigation.copyWith(
            routes: [
              ...base.uxSpec.navigation.routes,
              UxRouteNode(
                id: 'route_orpheline',
                path: '/parametres',
                title: 'Paramètres',
              ),
            ],
          ),
          screens: [
            // Altère SCR-001 (masterDetail) : west désactivé, 2 actions primaires, emptyStateTitle vide.
            base.uxSpec.screens.first.copyWith(
              zones: [
                UxScreenZoneSpec(
                  zone: UxLayoutZoneName.west,
                  enabled: false,
                  sizePx: 320,
                ),
                base.uxSpec.screens.first.zoneFor(UxLayoutZoneName.center)!,
              ],
              actions: [
                UxScreenAction(
                  id: 'act_p1',
                  label: 'Créer commande',
                  hierarchy: UxActionHierarchy.primary,
                ),
                UxScreenAction(
                  id: 'act_p2',
                  label: 'Valider tout',
                  hierarchy: UxActionHierarchy.primary,
                ),
              ],
              states: UxScreenStatesSpec.empty,
            ),
            ...base.uxSpec.screens.skip(1),
          ],
        ),
      );

      final issues = UxCoherenceAnalyzer.analyze(project);
      final orphanRouteIssues = issues
          .where((i) => i.code == 'COH-UX-NAV-002')
          .toList();
      expect(orphanRouteIssues, hasLength(1));
      expect(orphanRouteIssues.single.targetRef, 'route_orpheline');
      expect(orphanRouteIssues.single.severity, CoherenceSeverity.warning);

      final scrErgonomyIssues = issues
          .where((i) => i.code == 'COH-UX-SCR-002')
          .toList();
      expect(scrErgonomyIssues, hasLength(3));
      expect(
        scrErgonomyIssues.map((i) => i.id),
        containsAll(<String>[
          'ux_scr_master_detail_zones_scr_commandes',
          'ux_scr_multiple_primary_actions_scr_commandes',
          'ux_scr_empty_state_missing_scr_commandes',
        ]),
      );
    });

    test('détecte les exigences Must, cas d’usage et agrégats racines non couverts (COH-UX-COV-001)', () {
      final base = buildCoherentUxProject();
      final uncovered = base.copyWith(
        cahierDesCharges: base.cahierDesCharges.copyWith(
          functionalRequirements: [
            ...base.cahierDesCharges.functionalRequirements,
            FunctionalRequirement(
              id: 'req_must_uncovered',
              code: 'EXF-002',
              title: 'Export comptable obligatoire',
              moduleId: 'mod_cmd',
              priority: RequirementPriority.must,
              actorIds: const ['p_acheteur'],
            ),
            FunctionalRequirement(
              id: 'req_could_ignored',
              code: 'EXF-003',
              title: 'Mode hors-ligne optionnel',
              moduleId: 'mod_cmd',
              priority: RequirementPriority.could,
              actorIds: const ['p_acheteur'],
            ),
          ],
          useCases: [
            ...base.cahierDesCharges.useCases,
            UseCaseSpec(
              id: 'uc_uncovered',
              title: 'Clôturer un litige fournisseur',
              actorId: 'p_acheteur',
            ),
          ],
        ),
        businessObjects: [
          ...base.businessObjects,
          BusinessObjectSpec(
            id: 'obj_facture',
            name: 'Facture fournisseur',
            technicalName: 'FactureFournisseur',
            aggregateRoot: true,
            attributes: [
              BusinessAttribute(
                id: 'a_num_fac',
                name: 'numeroFacture',
                type: BusinessAttributeType.string,
                required: true,
              ),
            ],
          ),
        ],
      );

      final issues = UxCoherenceAnalyzer.analyze(uncovered);
      final covIssues = issues
          .where((i) => i.code == 'COH-UX-COV-001')
          .toList();
      expect(covIssues, hasLength(3));
      expect(
        covIssues.map((i) => i.targetRef).toSet(),
        equals(<String>{'EXF-002', 'uc_uncovered', 'obj_facture'}),
      );
      expect(covIssues.any((i) => i.targetRef == 'EXF-003'), isFalse);
    });

    test('détecte les termes proscrits et dépréciés du CompanyGlossary dans les libellés UX (COH-UX-LEX-001)', () {
      final base = buildCoherentUxProject();
      final glossary = buildSampleGlossary();

      final withForbiddenLabels = base.copyWith(
        uxSpec: base.uxSpec.copyWith(
          journeys: [
            base.uxSpec.journeys.single.copyWith(
              name: 'Saisie des devis papiers reçus',
            ),
          ],
          navigation: base.uxSpec.navigation.copyWith(
            routes: [
              base.uxSpec.navigation.routes.first.copyWith(
                title: 'Suivi Télécopie client',
              ),
              ...base.uxSpec.navigation.routes.skip(1),
            ],
          ),
          screens: [
            base.uxSpec.screens.first.copyWith(
              name: 'Gestion du bon volant',
              actions: [
                base.uxSpec.screens.first.actions.first.copyWith(
                  label: 'Créer un devis papier',
                ),
                ...base.uxSpec.screens.first.actions.skip(1),
              ],
            ),
            ...base.uxSpec.screens.skip(1),
          ],
        ),
      );

      final issues = UxCoherenceAnalyzer.analyze(
        withForbiddenLabels,
        companyGlossary: glossary,
      );
      final lexIssues = issues
          .where((i) => i.code == 'COH-UX-LEX-001')
          .toList();
      expect(lexIssues, hasLength(4));
      expect(
        lexIssues.every((i) => i.severity == CoherenceSeverity.warning),
        isTrue,
      );
      expect(
        lexIssues.map((i) => i.targetRef).toSet(),
        equals(<String>{
          'JRN-001',
          'route_commandes',
          'SCR-001',
          'scr_commandes.act_new',
        }),
      );
    });
  });

  group('UxMarkdownExporter & UxDesignMdExporter', () {
    test('UxMarkdownExporter.export génère les parcours, routes, écrans, zones, actions, états et matrice Métier↔UX', () {
      final project = buildCoherentUxProject();
      final markdown = UxMarkdownExporter.export(project);

      // En-tête, synthèse shell et identité visuelle.
      expect(
        markdown,
        contains('# Spécification UX & Parcours — B2B Order Studio'),
      );
      expect(markdown, contains('NavigationRail (`navigationRail`)'));
      expect(markdown, contains('`#0EA5E9`'));
      expect(markdown, contains('`Plus Jakarta Sans`'));

      // Parcours utilisateur JRN-001, étapes et critères de succès.
      expect(
        markdown,
        contains('### JRN-001 — Validation rapide d’une commande (`jrn_1`)'),
      );
      expect(markdown, contains('Acheteur B2B (`p_acheteur`)'));
      expect(markdown, contains('Consultation du portefeuille'));
      expect(markdown, contains('Validation complète en moins de 3 clics'));

      // Routes et diagramme Mermaid.
      expect(markdown, contains('`/commandes`'));
      expect(markdown, contains('`/commandes/nouvelle`'));
      expect(markdown, contains('`/commandes/bon-pdf`'));
      expect(markdown, contains('```mermaid'));
      expect(markdown, contains('flowchart LR'));

      // Fiches d'écrans (SCR-001..003), zones, slots liés, actions RG et états UX.
      expect(
        markdown,
        contains('### SCR-001 — Portefeuille des commandes (`scr_commandes`)'),
      );
      expect(markdown, contains('**Ouest** (`west`)'));
      expect(markdown, contains('**Centre** (`center`)'));
      expect(markdown, contains('`Commande` (`reference`, `statut`)'));
      expect(markdown, contains('`LigneCommande` (`designation`, `quantite`)'));
      expect(markdown, contains('**Nouvelle commande** (`act_new`)'));
      expect(markdown, contains('`RG-001`'));
      expect(
        markdown,
        contains(
          'Aucune commande B2B enregistrée _(CTA : « Créer la première commande »)_',
        ),
      );
      expect(markdown, contains('Bandeau d’alerte avec action Réessayer'));
      expect(markdown, contains('**Règles de lecture seule** : `RG-002`'));

      // Matrice complète de traçabilité Métier ↔ UX (sections 5.1 à 5.4).
      expect(markdown, contains('## 5. Matrice de traçabilité Métier ↔ UX'));
      expect(markdown, contains('### 5.1 Personas ↔ Parcours & Écrans'));
      expect(
        markdown,
        contains(
          '### 5.2 Cas d’usage & Exigences fonctionnelles ↔ Parcours & Écrans',
        ),
      );
      expect(markdown, contains('### 5.3 Objets métiers ↔ Écrans & Blocs UX'));
      expect(
        markdown,
        contains(
          '### 5.4 Règles de gestion (`RG-xxx`) ↔ Routes, Actions & États',
        ),
      );
      expect(markdown, contains('`EXF-001`'));
      expect(markdown, contains('`SCR-001` (Nouvelle commande)'));
      expect(markdown, contains('`SCR-002` (lecture seule)'));
    });

    test('UxDesignMdExporter.export se relit sans perte via DesignMdParser (accent, police, rayon, surfaceSystem, mode)', () {
      final darkGlassProject = buildCoherentUxProject();
      final designMd = UxDesignMdExporter.export(darkGlassProject);

      expect(designMd, startsWith('---\n'));
      expect(designMd, contains('# B2B Order Studio — DESIGN.md'));

      final parsedPreset = DesignMdParser.parseExternal(designMd);
      expect(parsedPreset.id, 'b2b-order-studio');
      expect(parsedPreset.name, 'B2B Order Studio');
      expect(parsedPreset.category, DesignSystemCategory.productivitySaas);
      expect(parsedPreset.palette.mode, ThemeMode.dark);
      expect(parsedPreset.palette.isDark, isTrue);
      expect(
        DesignSystemPalettePreview.colorToHex(parsedPreset.palette.accent),
        '#0EA5E9',
      );
      expect(parsedPreset.palette.fontHint, 'Plus Jakarta Sans');
      expect(parsedPreset.palette.cardRadius, 18.0);
      expect(parsedPreset.palette.surfaceSystem, DesignSystem.liquidGlass);
      expect(
        parsedPreset.tags,
        containsAll(<String>[
          'spec-forge',
          'navigationrail',
          'comfortable',
          'liquidglass',
        ]),
      );

      // Vérifie aussi une variante claire neumorphique.
      final lightNeumorphicProject = darkGlassProject.copyWith(
        uxSpec: darkGlassProject.uxSpec.copyWith(
          navigation: darkGlassProject.uxSpec.navigation.copyWith(
            visualTheme: const UxVisualThemeSeed(
              accentHex: '#10B981',
              themeMode: 'light',
              surfaceSystem: 'neumorphism',
              fontFamily: 'IBM Plex Sans',
              density: UxDensityProfile.compact,
              cardRadius: 12.0,
            ),
          ),
        ),
      );
      final lightPreset = DesignMdParser.parseExternal(
        UxDesignMdExporter.export(lightNeumorphicProject),
      );
      expect(lightPreset.palette.mode, ThemeMode.light);
      expect(
        DesignSystemPalettePreview.colorToHex(lightPreset.palette.accent),
        '#10B981',
      );
      expect(lightPreset.palette.fontHint, 'IBM Plex Sans');
      expect(lightPreset.palette.cardRadius, 12.0);
      expect(lightPreset.palette.surfaceSystem, DesignSystem.neumorphism);
    });
  });

  group('SpecSuperDesignerExporter (Appearance & SandboxedApplication)', () {
    test('buildInitialAppearance génère le catalogue de pages, les zones SuperLayout sans autoSides west/east, les liaisons repositories et les GoToPageAction', () {
      final project = buildCoherentUxProject();
      final appearance = SpecSuperDesignerExporter.buildInitialAppearance(
        project,
      );

      // Thème global aligné sur UxVisualThemeSeed.
      expect(appearance.mode, ThemeMode.dark);
      expect(appearance.accent, const Color(0xFF0EA5E9));
      expect(
        () => AppearanceTransfer.validateComponentRegions(appearance),
        returnsNormally,
      );
      expect(
        AppearanceTransfer.findIneffectiveLayoutStyleViolations(appearance),
        isEmpty,
      );

      // Catalogue de pages complet (standard, dialog, a4Document) et page d'accueil.
      final catalog = appearance.pageCatalog;
      expect(catalog.homePageId, 'route_commandes');
      expect(catalog.pages, hasLength(3));

      final stdPage = catalog.pages.firstWhere(
        (p) => p.id == 'route_commandes',
      );
      expect(stdPage.path, '/commandes');
      expect(stdPage.pageType, EditorPageType.standard);

      final dialogPage = catalog.pages.firstWhere(
        (p) => p.id == 'route_nouvelle_commande',
      );
      expect(dialogPage.path, '/commandes/nouvelle');
      expect(dialogPage.pageType, EditorPageType.dialog);
      expect(dialogPage.modalWidth, 640);
      expect(dialogPage.modalHeight, 520);

      final a4Page = catalog.pages.firstWhere((p) => p.id == 'route_bon_pdf');
      expect(a4Page.path, '/commandes/bon-pdf');
      expect(a4Page.pageType, EditorPageType.a4Document);

      // Structures racines des pages : ScaffoldPageConfig pour standard/dialog, A4PageConfig pour PDF.
      final stdScaffold =
          appearance.components[stdPage.id] as ScaffoldPageConfig;
      expect(stdScaffold.isEnabled(ScaffoldPageRegion.appBar), isTrue);
      expect(stdScaffold.isEnabled(ScaffoldPageRegion.body), isTrue);

      final dialogScaffold =
          appearance.components[dialogPage.id] as ScaffoldPageConfig;
      expect(dialogScaffold.isEnabled(ScaffoldPageRegion.appBar), isFalse);
      expect(dialogScaffold.isEnabled(ScaffoldPageRegion.body), isTrue);

      final a4Config = appearance.components[a4Page.id] as A4PageConfig;
      expect(a4Config.sheets, hasLength(1));

      // Zone Maître / Détail de la page standard et respect strict de la règle d'or sur autoSides.
      final stdBodyId = stdScaffold.slotsOf(ScaffoldPageRegion.body).single;
      final stdLayout = appearance.components[stdBodyId] as SuperLayoutConfig;
      expect(stdLayout.west, isTrue);
      expect(stdLayout.westSize, 320);
      expect(stdLayout.south, isTrue);
      expect(stdLayout.placements[SuperLayoutZone.west], isNotEmpty);
      expect(stdLayout.placements[SuperLayoutZone.center], isNotEmpty);

      final allLayouts = appearance.components.values
          .whereType<SuperLayoutConfig>()
          .toList();
      expect(allLayouts, isNotEmpty);
      for (final layout in allLayouts) {
        expect(layout.autoSides.contains(SuperLayoutZone.west), isFalse);
        expect(layout.autoSides.contains(SuperLayoutZone.east), isFalse);
      }

      // Liaisons repositories : collection racine 'commande' -> 'commandes' et gabarit '[?].attr'.
      final listConfigs = appearance.components.values
          .whereType<SuperListViewConfig>()
          .toList();
      expect(listConfigs, isNotEmpty);
      final masterList = listConfigs.firstWhere(
        (c) =>
            c.binding ==
            const JsonTextBinding(repositoryId: 'commande', path: 'commandes'),
      );
      expect(masterList.emptyText, 'Aucune commande B2B enregistrée');
      expect(masterList.template.autoSides, isEmpty);
      final rowFieldPaths = [
        for (final slotId in masterList.template.placedSlotIds)
          if (appearance.components[slotId] case final SuperValueConfig v)
            if (v.binding != null && v.binding!.repositoryId == null)
              v.binding!.path,
      ];
      expect(
        rowFieldPaths,
        containsAll(<String>['commandes[?].reference', 'commandes[?].statut']),
      );

      // Liaison imbriquée sur la table des lignes ('commandes[?].lignes') et cellules '[?].attr'.
      final tableConfigs = appearance.components.values
          .whereType<SuperTableConfig>()
          .toList();
      final linesTable = tableConfigs.firstWhere(
        (t) =>
            t.binding ==
            const JsonTextBinding(
              repositoryId: 'commande',
              path: 'commandes[?].lignes',
            ),
      );
      expect(linesTable.columns.map((c) => c.title), contains('Designation'));

      // Liaisons Maître/Détail et formulaire typé (checkbox booléen, sélecteur enum, lecture seule RG).
      final boundValues = appearance.components.values
          .whereType<SuperValueConfig>()
          .where((v) => v.binding?.repositoryId == 'commande')
          .toList();
      expect(
        boundValues.map((v) => v.binding!.path),
        containsAll(<String>[
          'commandes[?].reference',
          'commandes[?].montantHt',
          'commandes[?].estUrgente',
          'commandes[?].statut',
        ]),
      );
      expect(
        boundValues.any(
          (v) =>
              v.mode == SuperValueMode.input &&
              v.kind == SuperValueKind.checkbox &&
              v.readOnly &&
              v.binding?.path == 'commandes[?].estUrgente',
        ),
        isTrue,
      );
      expect(
        boundValues.any(
          (v) =>
              v.mode == SuperValueMode.input &&
              v.kind == SuperValueKind.choice &&
              v.readOnly &&
              v.binding?.path == 'commandes[?].statut',
        ),
        isTrue,
      );

      // Comportements de navigation GoToPageAction générés sur les boutons d'action et la barre de navigation.
      final goToActions = [
        for (final list in appearance.behaviors.values)
          for (final behavior in list)
            if (behavior.event == BehaviorEvent.onTap &&
                behavior.action is GoToPageAction)
              behavior.action as GoToPageAction,
      ];
      expect(
        goToActions.map((a) => a.pageId).toSet(),
        containsAll(<String?>[
          'route_nouvelle_commande',
          'route_bon_pdf',
          'route_commandes',
        ]),
      );
      expect(
        goToActions.map((a) => a.pagePath).toSet(),
        containsAll(<String>[
          '/commandes/nouvelle',
          '/commandes/bon-pdf',
          '/commandes',
        ]),
      );

      // Repli propre sur DefaultAppearance lorsque routes et écrans sont vides.
      final emptyUxAppearance =
          SpecSuperDesignerExporter.buildInitialAppearance(
            SpecForgeProject.fromIdea(idea: 'Application minimale'),
          );
      expect(emptyUxAppearance.pageCatalog.pages, isEmpty);
    });

    test('exportToSandboxedApplication crée tous les artefacts UX/SuperDesigner et se recharge proprement via SandboxedApplicationStore.appearanceStoreFor', () async {
      final project = buildCoherentUxProject();
      final expectedAppearance =
          SpecSuperDesignerExporter.buildInitialAppearance(project);
      final sep = Platform.pathSeparator;
      final tempRoot = await Directory.systemTemp.createTemp(
        'spec_forge_ux_sandbox_',
      );

      try {
        final appDir = Directory('${tempRoot.path}${sep}b2b_order_studio');
        final manifest =
            await SpecSuperDesignerExporter.exportToSandboxedApplication(
              project,
              appDir,
            );
        expect(manifest.name, 'B2B Order Studio');

        // 1. app.json
        final appJsonFile = SandboxedApplicationStore.manifestFileFor(appDir);
        expect(await appJsonFile.exists(), isTrue);
        final parsedManifest = SandboxedApplicationManifest.fromJson(
          jsonDecode(await appJsonFile.readAsString()),
        );
        expect(parsedManifest.name, 'B2B Order Studio');

        // 2. repositories/ et repositories/design_systems/
        final reposDir = SandboxedApplicationStore.repositoriesDirectoryFor(
          appDir,
        );
        expect(await reposDir.exists(), isTrue);
        expect(
          await File('${reposDir.path}${sep}registered${sep}commande.json')
              .exists(),
          isTrue,
        );

        final designSystemsDir = Directory(
          '${reposDir.path}${sep}design_systems',
        );
        expect(await designSystemsDir.exists(), isTrue);
        expect(
          await File('${designSystemsDir.path}${sep}b2b-order-studio.md')
              .exists(),
          isTrue,
        );

        final verifyRepoStore = SandboxedApplicationStore.repositoryStoreFor(
          appDir,
        );
        try {
          final savedDesignPresets =
              await CustomDesignSystemStore.forRepositoryStore(verifyRepoStore)
                  .loadAll();
          expect(savedDesignPresets, hasLength(1));
          expect(savedDesignPresets.single.id, 'b2b-order-studio');
        } finally {
          verifyRepoStore.dispose();
        }

        // 3. DESIGN.md et spec_forge_ux.md à la racine de l'application sandboxée
        final designMdFile = File('${appDir.path}${sep}DESIGN.md');
        expect(await designMdFile.exists(), isTrue);
        final reloadedPreset = DesignMdParser.parseExternal(
          await designMdFile.readAsString(),
        );
        expect(
          DesignSystemPalettePreview.colorToHex(reloadedPreset.palette.accent),
          '#0EA5E9',
        );

        final uxMdFile = File('${appDir.path}${sep}spec_forge_ux.md');
        expect(await uxMdFile.exists(), isTrue);
        final uxMdContent = await uxMdFile.readAsString();
        expect(uxMdContent, contains('JRN-001'));
        expect(uxMdContent, contains('SCR-001'));

        // 4. appearance.json et pages/*.json rechargés via SandboxedApplicationStore.appearanceStoreFor
        final appearanceFile = SandboxedApplicationStore.appearanceFileFor(
          appDir,
        );
        final pagesDir = SandboxedApplicationStore.pagesDirectoryFor(appDir);
        expect(await appearanceFile.exists(), isTrue);
        expect(await pagesDir.exists(), isTrue);

        for (final page in expectedAppearance.pageCatalog.pages) {
          final pageFile = SandboxedApplicationStore.pageFileFor(
            appDir,
            page.id,
          );
          expect(
            await pageFile.exists(),
            isTrue,
            reason: 'Fichier de page manquant pour ${page.id}',
          );
        }

        final appearanceStore = SandboxedApplicationStore.appearanceStoreFor(
          appDir,
        );
        var reloadedAppearance = await appearanceStore.load();
        expect(reloadedAppearance.mode, ThemeMode.dark);
        expect(reloadedAppearance.accent, const Color(0xFF0EA5E9));
        expect(
          reloadedAppearance.pageCatalog.homePageId,
          expectedAppearance.pageCatalog.homePageId,
        );
        expect(
          reloadedAppearance.pageCatalog.pages.map((p) => p.id).toList(),
          equals(
            expectedAppearance.pageCatalog.pages.map((p) => p.id).toList(),
          ),
        );

        for (final page in reloadedAppearance.pageCatalog.pages) {
          final slice = await appearanceStore.loadPage(page.id);
          expect(slice.isEmpty, isFalse);
          expect(slice.components.containsKey(page.id), isTrue);
          reloadedAppearance = slice.mergeInto(reloadedAppearance);
        }

        expect(
          reloadedAppearance.components.keys,
          containsAll(expectedAppearance.components.keys),
        );
        expect(
          reloadedAppearance.behaviors.keys,
          containsAll(expectedAppearance.behaviors.keys),
        );
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });

    test('exportUxAndSuperDesignerDirectory écrit json_schemas, repositories et prompt_super_designer.md sans HTML', () async {
      final project = buildCoherentUxProject();
      final sep = Platform.pathSeparator;
      final tempRoot = await Directory.systemTemp.createTemp(
        'spec_forge_ux_export_dir_',
      );

      try {
        final outDir = Directory('${tempRoot.path}${sep}export_out');
        await outDir.create(recursive: true);
        // Dépose un ancien fichier HTML pour vérifier qu'il est supprimé à la ré-exportation.
        await File('${outDir.path}${sep}specification_ux.html')
            .writeAsString('<html>legacy</html>', flush: true);

        await SpecSuperDesignerExporter.exportUxAndSuperDesignerDirectory(
          project,
          outDir,
          includeSandboxedApp: true,
        );

        // Aucun fichier HTML généré.
        expect(
          await File('${outDir.path}${sep}specification_ux.html').exists(),
          isFalse,
        );

        // Prompt pour le Vibe Chat de SuperDesigner présent à la racine et dans super_designer_app/.
        final promptFile = File('${outDir.path}${sep}prompt_super_designer.md');
        expect(await promptFile.exists(), isTrue);
        final promptText = await promptFile.readAsString();
        expect(
          promptText,
          contains('# Prompt Vibe Chat SuperDesigner — B2B Order Studio'),
        );
        expect(promptText, contains('`commande.commandes`'));
        expect(promptText, contains('`ligne_commande.ligne_commandes`'));
        expect(promptText, contains('SCR-001 — Portefeuille des commandes'));
        expect(promptText, contains('RG-001 — Validation'));
        expect(promptText, contains('JRN-001 — Validation rapide'));
        expect(
          await File(
            '${outDir.path}${sep}super_designer_app${sep}prompt_super_designer.md',
          ).exists(),
          isTrue,
        );

        // Tous les objets métiers (y compris aggregateRoot: false) disposent de leur JSON Schema et de leur repository.
        final cmdSchemaFile = File(
          '${outDir.path}${sep}json_schemas${sep}commande.schema.json',
        );
        final lineSchemaFile = File(
          '${outDir.path}${sep}json_schemas${sep}ligne_commande.schema.json',
        );
        final cmdRepoFile = File(
          '${outDir.path}${sep}repositories${sep}commande.json',
        );
        final lineRepoFile = File(
          '${outDir.path}${sep}repositories${sep}ligne_commande.json',
        );
        expect(await cmdSchemaFile.exists(), isTrue);
        expect(await lineSchemaFile.exists(), isTrue);
        expect(await cmdRepoFile.exists(), isTrue);
        expect(await lineRepoFile.exists(), isTrue);

        final cmdSchema =
            jsonDecode(await cmdSchemaFile.readAsString())
                as Map<String, Object?>;
        final cmdRepo =
            jsonDecode(await cmdRepoFile.readAsString())
                as Map<String, Object?>;
        expect(JsonSchemaValidator.validate(cmdRepo, cmdSchema).isValid, isTrue);

        expect(
          await File('${outDir.path}${sep}repositories_bundle.json').exists(),
          isTrue,
        );
        expect(
          await File('${outDir.path}${sep}schema_light.yaml').exists(),
          isTrue,
        );
        expect(await File('${outDir.path}${sep}DESIGN.md').exists(), isTrue);
        expect(
          await File('${outDir.path}${sep}specification_ux.md').exists(),
          isTrue,
        );
        expect(
          await File('${outDir.path}${sep}specification_ux.json').exists(),
          isTrue,
        );
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });
  });
}
