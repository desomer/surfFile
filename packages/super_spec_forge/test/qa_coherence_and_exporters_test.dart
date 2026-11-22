/// Tests unitaires de l'analyseur de couverture 360° QA ([QaCoherenceAnalyzer]), de l'amorceur déterministe ([QaAutoSeeder]) et des exportateurs BDD/Gherkin & TDD ([GherkinFeatureExporter], [QaMarkdownExporter], [QaTddPromptExporter], [QaDirectoryExporter]).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart'
    show EditorPageType;
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

  SpecForgeProject buildUncoveredFullProject() {
    final base = SpecForgeProject.fromIdea(
      idea: 'Portail de pilotage et validation des commandes B2B',
      name: 'B2B Order QA Studio',
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
        conventions: const ['Montants en EUR HT à 2 décimales'],
      ),
      vision: base.vision.copyWith(
        problemStatement: 'Commandes B2B saisies sans contrôle automatique.',
        valueProposition:
            'Validation instantanée des commandes B2B avec garde-fous métier.',
        objectives: const ['Zéro commande hors plafond validée sans contrôle'],
        personas: [
          SpecPersona(
            id: 'p_acheteur',
            name: 'Acheteur B2B',
            role: 'Prépare, contrôle et valide les commandes fournisseurs',
            goals: const ['Valider une commande conforme rapidement'],
          ),
        ],
      ),
      cahierDesCharges: SpecCahierDesCharges(
        modules: const [
          SpecModule(
            id: 'mod_cmd',
            name: 'Commandes',
            description: 'Cycle complet de saisie et validation des commandes',
          ),
        ],
        functionalRequirements: [
          FunctionalRequirement(
            id: 'req_1',
            code: 'EXF-001',
            title: 'Création et validation d’une commande B2B',
            moduleId: 'mod_cmd',
            priority: RequirementPriority.must,
            actorIds: const ['p_acheteur'],
            acceptanceCriteria: const [
              'La commande passe au statut validee lorsque le montant HT respecte le plafond',
            ],
          ),
          FunctionalRequirement(
            id: 'req_2',
            code: 'EXF-002',
            title: 'Contrôle automatique du plafond d’engagement HT',
            moduleId: 'mod_cmd',
            priority: RequirementPriority.should,
            actorIds: const ['p_acheteur'],
            acceptanceCriteria: const [
              'Toute commande dépassant 50000 EUR HT est rejetée avec un motif explicite',
            ],
          ),
        ],
        useCases: [
          UseCaseSpec(
            id: 'uc_1',
            title: 'Soumettre et valider une commande B2B',
            actorId: 'p_acheteur',
            preconditions: const ['L’acheteur B2B est authentifié'],
            mainFlow: const [
              'Sélectionner une commande brouillon dans le portefeuille',
              'Déclencher l’action de validation métier',
            ],
            alternativeFlows: const [
              'Le système rejette la validation si le montant HT dépasse le plafond autorisé',
            ],
            postconditions: const [
              'La commande est enregistrée à l’état validee',
            ],
          ),
        ],
      ),
      businessObjects: [
        BusinessObjectSpec(
          id: 'obj_commande',
          name: 'Commande',
          technicalName: 'Commande',
          description: 'Agrégat racine représentant une commande B2B',
          aggregateRoot: true,
          attributes: [
            BusinessAttribute(
              id: 'a_ref',
              name: 'reference',
              type: BusinessAttributeType.string,
              required: true,
              schemaConstraints: JsonSchemaConstraints(
                minLength: 4,
                maxLength: 24,
              ),
            ),
            BusinessAttribute(
              id: 'a_montant',
              name: 'montantHt',
              type: BusinessAttributeType.number,
              required: true,
              schemaConstraints: JsonSchemaConstraints(
                minimum: 10,
                maximum: 50000,
              ),
            ),
            BusinessAttribute(
              id: 'a_statut',
              name: 'statut',
              type: BusinessAttributeType.enumeration,
              required: true,
              enumValues: const ['brouillon', 'validee', 'rejetee'],
            ),
          ],
          relations: const [
            BusinessRelation(
              id: 'rel_lignes',
              name: 'lignes',
              targetObjectId: 'obj_ligne_commande',
              cardinality: BusinessRelationCardinality.oneToMany,
              required: true,
            ),
          ],
          lifecycleStates: const [
            LifecycleState(name: 'brouillon', isInitial: true),
            LifecycleState(name: 'validee', isTerminal: true),
            LifecycleState(name: 'rejetee', isTerminal: true),
          ],
          lifecycleTransitions: const [
            LifecycleTransition(
              id: 'tr_valider',
              fromState: 'brouillon',
              toState: 'validee',
              trigger: 'Validation acheteur',
              guardSummary: 'montantHt <= 50000',
            ),
          ],
        ),
        BusinessObjectSpec(
          id: 'obj_ligne_commande',
          name: 'Ligne de commande',
          technicalName: 'LigneCommande',
          description: 'Poste unitaire rattaché à une commande B2B',
          aggregateRoot: false,
          attributes: [
            BusinessAttribute(
              id: 'a_sku',
              name: 'codeArticle',
              type: BusinessAttributeType.string,
              required: true,
              schemaConstraints: JsonSchemaConstraints(minLength: 3),
            ),
            BusinessAttribute(
              id: 'a_qte',
              name: 'quantite',
              type: BusinessAttributeType.integer,
              required: true,
              schemaConstraints: JsonSchemaConstraints(minimum: 1),
            ),
          ],
        ),
      ],
      businessRules: [
        BusinessRuleSpec(
          id: 'rg_1',
          code: 'RG-001',
          title: 'Plafond maximal de validation d’une commande B2B',
          category: BusinessRuleCategory.validation,
          targetObjectIds: const ['obj_commande'],
          trigger: 'Validation d’une commande brouillon',
          condition: 'montantHt <= 50000',
          effect: 'Autorise le passage au statut validee',
          errorMessage: 'Montant HT supérieur au plafond autorisé (50000 EUR)',
        ),
        BusinessRuleSpec(
          id: 'rg_2',
          code: 'RG-002',
          title: 'Quantité minimale stricte par ligne de commande',
          category: BusinessRuleCategory.calculation,
          targetObjectIds: const ['obj_ligne_commande'],
          trigger: 'Ajout ou modification d’une ligne de commande',
          condition: 'quantite >= 1',
          effect: 'Calcule le sous-total de la ligne',
          errorMessage: 'La quantité commandée doit être au moins égale à 1',
        ),
      ],
      uxSpec: UxForgeSpec(
        currentStage: UxForgeStage.uxReviewExport,
        journeys: [
          UxJourneySpec(
            id: 'jrn_1',
            code: 'JRN-001',
            name: 'Validation d’une commande B2B',
            personaId: 'p_acheteur',
            useCaseIds: const ['uc_1'],
            requirementIds: const ['EXF-001', 'EXF-002'],
            channel: UxTargetChannel.desktop,
            trigger: 'Réception d’une demande d’achat validable',
            goal: 'Contrôler et valider la commande sans ressaisie',
            steps: const [
              UxJourneyStep(
                id: 'jstep_1',
                order: 1,
                title: 'Sélection dans le portefeuille',
                actorAction: 'Sélectionne la commande dans la liste maître',
                systemResponse: 'Affiche le détail et les lignes de commande',
                targetRouteId: 'route_commandes',
              ),
              UxJourneyStep(
                id: 'jstep_2',
                order: 2,
                title: 'Contrôle en modale de validation',
                actorAction: 'Ouvre la confirmation de validation',
                systemResponse: 'Affiche le récapitulatif de contrôle plafond',
                targetRouteId: 'route_validation',
              ),
            ],
            successCriteria: const ['Commande validée en moins de 3 clics'],
          ),
        ],
        navigation: UxNavigationSpec(
          shellPattern: UxShellPattern.navigationRail,
          homeRouteId: 'route_commandes',
          routes: [
            UxRouteNode(
              id: 'route_commandes',
              path: '/commandes',
              title: 'Portefeuille Commandes',
              pageType: EditorPageType.standard,
              moduleId: 'mod_cmd',
              allowedPersonaIds: const ['p_acheteur'],
            ),
            UxRouteNode(
              id: 'route_validation',
              path: '/commandes/validation',
              title: 'Validation Commande',
              pageType: EditorPageType.dialog,
              moduleId: 'mod_cmd',
              parentRouteId: 'route_commandes',
              allowedPersonaIds: const ['p_acheteur'],
              showInPrimaryNav: false,
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
            purpose: 'Consulter et valider les commandes B2B.',
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
                    id: 'slot_list_cmd',
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
                    id: 'slot_detail_cmd',
                    title: 'Fiche commande',
                    kind: UxWidgetKind.detailCard,
                    businessObjectId: 'obj_commande',
                    attributeNames: const ['reference', 'montantHt', 'statut'],
                  ),
                  UxZoneWidgetSlot(
                    id: 'slot_table_lines',
                    title: 'Lignes de la commande',
                    kind: UxWidgetKind.dataTable,
                    businessObjectId: 'obj_ligne_commande',
                    attributeNames: const ['codeArticle', 'quantite'],
                  ),
                ],
              ),
            ],
            actions: [
              UxScreenAction(
                id: 'act_open_val',
                label: 'Valider la commande',
                hierarchy: UxActionHierarchy.primary,
                businessRuleIds: const ['RG-001'],
                targetRouteId: 'route_validation',
              ),
            ],
            states: UxScreenStatesSpec(
              emptyStateTitle: 'Aucune commande enregistrée',
              emptyStateCta: 'Créer une commande',
            ),
          ),
          UxScreenSpec(
            id: 'scr_validation',
            code: 'SCR-002',
            name: 'Confirmation de validation',
            routeId: 'route_validation',
            pattern: UxScreenPattern.form,
            purpose: 'Vérifier le plafond HT avant validation définitive.',
            personaIds: const ['p_acheteur'],
            requirementIds: const ['EXF-002'],
            primaryObjectId: 'obj_commande',
            zones: [
              UxScreenZoneSpec(
                zone: UxLayoutZoneName.center,
                slots: [
                  UxZoneWidgetSlot(
                    id: 'slot_form_val',
                    title: 'Récapitulatif financier',
                    kind: UxWidgetKind.formSection,
                    businessObjectId: 'obj_commande',
                    attributeNames: const ['reference', 'montantHt'],
                  ),
                ],
              ),
            ],
            actions: [
              UxScreenAction(
                id: 'act_confirm_val',
                label: 'Confirmer la validation',
                hierarchy: UxActionHierarchy.primary,
                businessRuleIds: const ['RG-001'],
                targetRouteId: 'route_commandes',
              ),
            ],
            states: UxScreenStatesSpec(
              emptyStateTitle: 'Sélectionnez une commande à contrôler',
            ),
          ),
        ],
      ),
    );
  }

  SpecForgeProject buildCoherentFullProject() {
    final base = buildUncoveredFullProject();
    return base.copyWith(
      qaSpec: QaForgeSpec(
        currentStage: QaForgeStage.qaReviewExport,
        gherkinLanguage: GherkinKeywordLanguage.fr,
        fixtures: [
          QaFixtureSpec(
            id: 'fix_cmd_nominal',
            code: 'FIX-001',
            name: 'Commande nominale conforme',
            kind: QaFixtureKind.nominal,
            businessObjectId: 'obj_commande',
            personaId: 'p_acheteur',
            businessRuleIds: const ['RG-001'],
            description: 'Commande brouillon standard sous le plafond HT.',
            payload: const <String, Object?>{
              'reference': 'CMD-2026-001',
              'montantHt': 1250.0,
              'statut': 'brouillon',
            },
            expectedValid: true,
          ),
          QaFixtureSpec(
            id: 'fix_cmd_hors_plafond',
            code: 'FIX-002',
            name: 'Commande dépassant le plafond HT',
            kind: QaFixtureKind.invalid,
            businessObjectId: 'obj_commande',
            personaId: 'p_acheteur',
            businessRuleIds: const ['RG-001'],
            description: 'Commande invalide au-delà de 50000 EUR HT.',
            payload: const <String, Object?>{
              'reference': 'CMD-2026-999',
              'montantHt': 75000.0,
              'statut': 'brouillon',
            },
            expectedValid: false,
            expectedErrorHint:
                'Montant HT supérieur au plafond autorisé (50000 EUR)',
          ),
          QaFixtureSpec(
            id: 'fix_ligne_nominale',
            code: 'FIX-003',
            name: 'Ligne de commande standard',
            kind: QaFixtureKind.boundary,
            businessObjectId: 'obj_ligne_commande',
            personaId: 'p_acheteur',
            businessRuleIds: const ['RG-002'],
            description: 'Ligne valide à la borne minimale quantite = 1.',
            payload: const <String, Object?>{
              'codeArticle': 'ART-100',
              'quantite': 1,
            },
            expectedValid: true,
          ),
        ],
        features: [
          GherkinFeatureSpec(
            id: 'feat_validation_cmd',
            code: 'FEAT-001',
            title: 'Validation et contrôle plafond des commandes B2B',
            moduleId: 'mod_cmd',
            personaId: 'p_acheteur',
            narrative:
                'En tant qu’Acheteur B2B\n'
                'Je veux valider une commande conforme et bloquer tout dépassement de plafond\n'
                'Afin de sécuriser les engagements financiers fournisseurs',
            tags: const ['commandes', '@smoke'],
            backgroundSteps: [
              GherkinStep(
                id: 'bg_1',
                keyword: GherkinStepKeyword.given,
                text: 'que l’acheteur habilité est connecté au portefeuille des commandes',
              ),
            ],
            scenarios: [
              GherkinScenarioSpec(
                id: 'scn_val_nominale',
                code: 'SCN-001',
                title: 'Validation nominale d’une commande B2B conforme',
                tags: const ['nominal'],
                steps: [
                  GherkinStep(
                    id: 'st_1',
                    keyword: GherkinStepKeyword.given,
                    text: 'une commande brouillon conforme chargée depuis la fixture FIX-001',
                    dataTable: const <List<String>>[
                      <String>['reference', 'montantHt'],
                      <String>['CMD-2026-001', '1250.00'],
                    ],
                  ),
                  GherkinStep(
                    id: 'st_2',
                    keyword: GherkinStepKeyword.when,
                    text: 'l’acheteur confirme la validation de la commande',
                  ),
                  GherkinStep(
                    id: 'st_3',
                    keyword: GherkinStepKeyword.then,
                    text: 'la commande passe au statut "validee"',
                    docString: '{"statut": "validee"}',
                  ),
                  GherkinStep(
                    id: 'st_4',
                    keyword: GherkinStepKeyword.and,
                    text: 'une notification de confirmation est affichée',
                  ),
                  GherkinStep(
                    id: 'st_5',
                    keyword: GherkinStepKeyword.but,
                    text: 'aucune alerte de dépassement n’est émise',
                  ),
                ],
                requirementIds: const ['EXF-001'],
                useCaseIds: const ['uc_1'],
                businessRuleIds: const ['RG-001'],
                journeyIds: const ['JRN-001'],
                screenIds: const ['SCR-001', 'SCR-002'],
                fixtureIds: const ['FIX-001', 'FIX-003'],
              ),
              GherkinScenarioSpec(
                id: 'scn_outline_plafond',
                code: 'SCN-002',
                title: 'Contrôle paramétré du plafond HT à la validation',
                isOutline: true,
                tags: const ['@plafond'],
                steps: [
                  GherkinStep(
                    id: 'sto_1',
                    keyword: GherkinStepKeyword.given,
                    text: 'une commande brouillon de montant HT égal à <montant_ht> EUR',
                  ),
                  GherkinStep(
                    id: 'sto_2',
                    keyword: GherkinStepKeyword.when,
                    text: 'l’acheteur soumet la commande pour validation',
                  ),
                  GherkinStep(
                    id: 'sto_3',
                    keyword: GherkinStepKeyword.then,
                    text: 'le statut résultant est "<statut_attendu>"',
                  ),
                ],
                examples: GherkinExamplesTable(
                  headers: const ['montant_ht', 'statut_attendu'],
                  rows: const <List<String>>[
                    <String>['1250.00', 'validee'],
                    <String>['50000.00', 'validee'],
                    <String>['75000.00', 'rejetee | hors plafond'],
                  ],
                ),
                requirementIds: const ['EXF-002'],
                businessRuleIds: const ['RG-001'],
                screenIds: const ['SCR-002'],
                fixtureIds: const ['FIX-001', 'FIX-002'],
              ),
            ],
          ),
        ],
        tddSuites: [
          TddTestSuiteSpec(
            id: 'tdd_commande_rules',
            code: 'TDD-001',
            name: 'Validation métier et calculs sur Commande B2B',
            layer: TddTargetLayer.domainValidation,
            targetObjectId: 'obj_commande',
            moduleId: 'mod_cmd',
            description: 'Vérifie en Red → Green → Refactor le plafond RG-001 et la quantité minimale RG-002.',
            cases: [
              TddTestCaseSpec(
                id: 'tc_val_ok',
                code: 'TC-001',
                order: 1,
                title: 'Autorise la validation d’une commande sous le plafond',
                fixtureId: 'FIX-001',
                arrange: 'Instancier la commande brouillon de FIX-001',
                act: 'commandeValidator.validate(commande)',
                outcomeKind: TddExpectedOutcomeKind.mutatesState,
                assertExpected: 'commande.statut == "validee"',
                businessRuleIds: const ['RG-001'],
                requirementIds: const ['EXF-001'],
                screenIds: const ['SCR-001'],
              ),
              TddTestCaseSpec(
                id: 'tc_val_plafond_ko',
                code: 'TC-002',
                order: 2,
                title: 'Rejette une commande dépassant 50000 EUR HT',
                fixtureId: 'FIX-002',
                arrange: 'Instancier la commande hors plafond de FIX-002',
                act: 'commandeValidator.validate(commande)',
                outcomeKind: TddExpectedOutcomeKind.rejectsWithError,
                assertExpected: 'La commande demeure en statut brouillon',
                expectedErrorMessage:
                    'Montant HT supérieur au plafond autorisé (50000 EUR)',
                businessRuleIds: const ['RG-001'],
                requirementIds: const ['EXF-002'],
                screenIds: const ['SCR-002'],
              ),
              TddTestCaseSpec(
                id: 'tc_ligne_qte_min',
                code: 'TC-003',
                order: 3,
                title: 'Calcule le sous-total dès quantite >= 1',
                fixtureId: 'FIX-003',
                arrange: 'Charger la ligne de commande nominale FIX-003',
                act: 'ligneCalculator.computeQuantityCheck(ligne)',
                outcomeKind: TddExpectedOutcomeKind.returnsValue,
                assertExpected: 'Retourne quantite valide égale à 1',
                businessRuleIds: const ['RG-002'],
              ),
            ],
          ),
        ],
      ),
    );
  }

  SpecForgeProject buildCoherentBackendOnlyProject() {
    final full = buildCoherentFullProject();
    return full.copyWith(
      name: 'Headless Order Engine API',
      uxSpec: UxForgeSpec.empty,
      qaSpec: full.qaSpec.copyWith(
        features: [
          for (final feature in full.qaSpec.features)
            feature.copyWith(
              scenarios: [
                for (final sc in feature.scenarios)
                  sc.copyWith(
                    journeyIds: const <String>[],
                    screenIds: const <String>[],
                  ),
              ],
            ),
        ],
        tddSuites: [
          for (final suite in full.qaSpec.tddSuites)
            suite.copyWith(
              cases: [
                for (final tc in suite.cases)
                  tc.copyWith(screenIds: const <String>[]),
              ],
            ),
        ],
      ),
    );
  }

  group('QaCoherenceAnalyzer.analyze', () {
    test('retourne zéro erreur et zéro avertissement sur un projet complet Métier + UX + QA cohérent ainsi que sur un projet purement Backend Métier + QA sans UX', () {
      final fullProject = buildCoherentFullProject();
      final glossary = buildSampleGlossary();

      expect(fullProject.validate, returnsNormally);
      expect(
        SpecForgeProject.fromJson(fullProject.toJson()),
        equals(fullProject),
      );
      expect(
        SpecCoherenceAnalyzer.analyze(fullProject, companyGlossary: glossary),
        isEmpty,
      );
      expect(
        UxCoherenceAnalyzer.analyze(fullProject, companyGlossary: glossary),
        isEmpty,
      );
      expect(
        QaCoherenceAnalyzer.analyze(fullProject, companyGlossary: glossary),
        isEmpty,
      );

      // Projet purement Backend / API sans UX (uxSpec vide).
      final backendProject = buildCoherentBackendOnlyProject();
      expect(backendProject.uxSpec.journeys, isEmpty);
      expect(backendProject.uxSpec.screens, isEmpty);
      expect(backendProject.validate, returnsNormally);
      expect(
        SpecCoherenceAnalyzer.analyze(
          backendProject,
          companyGlossary: glossary,
        ),
        isEmpty,
      );
      expect(
        QaCoherenceAnalyzer.analyze(backendProject, companyGlossary: glossary),
        isEmpty,
      );
    });

    test('détecte les objets métiers sans fixture et les métadonnées de fixtures invalides (COH-QA-FIX-001)', () {
      final base = buildCoherentFullProject();
      final mutated = base.copyWith(
        businessObjects: [
          ...base.businessObjects,
          BusinessObjectSpec(
            id: 'obj_remise',
            name: 'Remise commerciale',
            technicalName: 'RemiseCommerciale',
            attributes: [
              BusinessAttribute(
                id: 'a_taux',
                name: 'tauxPourcent',
                type: BusinessAttributeType.number,
                required: true,
              ),
            ],
          ),
        ],
        qaSpec: base.qaSpec.copyWith(
          fixtures: [
            ...base.qaSpec.fixtures,
            QaFixtureSpec(
              id: 'fix_broken_refs',
              code: 'FIX-090',
              name: 'Fixture avec références fantômes',
              kind: QaFixtureKind.nominal,
              businessObjectId: 'obj_introuvable',
              personaId: 'p_fantome',
              businessRuleIds: const ['RG-999'],
              expectedValid: true,
            ),
            QaFixtureSpec(
              id: 'fix_negative_without_reason',
              code: 'FIX-091',
              name: 'Fixture négative muette',
              kind: QaFixtureKind.invalid,
              businessObjectId: 'obj_commande',
              expectedValid: false,
              expectedErrorHint: '',
              businessRuleIds: const <String>[],
            ),
          ],
        ),
      );

      final issues = QaCoherenceAnalyzer.analyze(mutated);
      final fixIssues = issues
          .where((i) => i.code == 'COH-QA-FIX-001')
          .toList();

      // 5 anomalies COH-QA-FIX-001 :
      // - 1 warning objet métier sans fixture (obj_remise)
      // - 3 erreurs sur FIX-090 (objet inconnu, persona inconnu, règle inconnue)
      // - 1 warning sur FIX-091 (expectedValid == false sans expectedErrorHint ni RG)
      expect(fixIssues, hasLength(5));
      expect(
        fixIssues.every((i) => i.stage == QaForgeStage.testFixtures),
        isTrue,
      );
      expect(
        fixIssues.where((i) => i.severity == CoherenceSeverity.error),
        hasLength(3),
      );
      expect(
        fixIssues.where((i) => i.severity == CoherenceSeverity.warning),
        hasLength(2),
      );
      expect(
        fixIssues.map((i) => i.id),
        containsAll(<String>[
          'qa_fix_uncovered_obj_obj_remise',
          'qa_fix_missing_error_hint_fix_negative_without_reason',
        ]),
      );
    });

    test('détecte l’absence d’étape Alors/Then, les incohérences <variable> ↔ Exemples des Scenario Outlines (COH-QA-GHK-001) et les références cassées (COH-QA-GHK-002)', () {
      final base = buildCoherentFullProject();
      final mutated = base.copyWith(
        qaSpec: base.qaSpec.copyWith(
          features: [
            ...base.qaSpec.features,
            GherkinFeatureSpec(
              id: 'feat_empty',
              code: 'FEAT-090',
              title: 'Fonctionnalité coquille vide',
              moduleId: 'mod_fantome',
              personaId: 'p_inconnu',
              scenarios: const <GherkinScenarioSpec>[],
            ),
            GherkinFeatureSpec(
              id: 'feat_broken_ghk',
              code: 'FEAT-091',
              title: 'Fonctionnalité avec scénarios défectueux',
              scenarios: [
                GherkinScenarioSpec(
                  id: 'scn_no_steps',
                  code: 'SCN-090',
                  title: 'Scénario sans aucune étape',
                  steps: const <GherkinStep>[],
                ),
                GherkinScenarioSpec(
                  id: 'scn_no_then',
                  code: 'SCN-091',
                  title: 'Scénario sans vérification Alors/Then',
                  steps: [
                    GherkinStep(
                      id: 's1',
                      keyword: GherkinStepKeyword.given,
                      text: 'un contexte initial valide',
                    ),
                    GherkinStep(
                      id: 's2',
                      keyword: GherkinStepKeyword.when,
                      text: 'l’utilisateur déclenche l’action',
                    ),
                  ],
                  requirementIds: const ['EXF-404'],
                  useCaseIds: const ['uc_404'],
                  businessRuleIds: const ['RG-404'],
                  journeyIds: const ['JRN-404'],
                  screenIds: const ['SCR-404'],
                  fixtureIds: const ['FIX-404'],
                ),
                GherkinScenarioSpec(
                  id: 'scn_outline_mismatch',
                  code: 'SCN-092',
                  title: 'Plan du scénario aux variables désalignées',
                  isOutline: true,
                  steps: [
                    GherkinStep(
                      id: 'so1',
                      keyword: GherkinStepKeyword.given,
                      text: 'un montant saisi de <montant_saisi>',
                    ),
                    GherkinStep(
                      id: 'so2',
                      keyword: GherkinStepKeyword.when,
                      text: 'le canal <canal_inconnu> soumet la commande',
                    ),
                    GherkinStep(
                      id: 'so3',
                      keyword: GherkinStepKeyword.then,
                      text: 'le résultat est calculé',
                    ),
                  ],
                  examples: GherkinExamplesTable(
                    headers: const ['montant_saisi', 'colonne_inutilisee'],
                    rows: const <List<String>>[],
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      final issues = QaCoherenceAnalyzer.analyze(mutated);
      final ghkSyntaxIssues = issues
          .where((i) => i.code == 'COH-QA-GHK-001')
          .toList();
      final ghkRefIssues = issues
          .where((i) => i.code == 'COH-QA-GHK-002')
          .toList();

      // 6 anomalies COH-QA-GHK-001 :
      // - feature sans scénario (warning)
      // - scénario sans étape (error)
      // - scénario sans étape Then/Alors (warning)
      // - outline sans lignes d'exemples (error)
      // - variable <canal_inconnu> absente des en-têtes Exemples (error)
      // - colonne colonne_inutilisee non référencée dans les étapes (warning)
      expect(ghkSyntaxIssues, hasLength(6));
      expect(
        ghkSyntaxIssues.map((i) => i.id),
        containsAll(<String>[
          'qa_ghk_empty_feature_feat_empty',
          'qa_ghk_empty_steps_feat_broken_ghk_scn_no_steps',
          'qa_ghk_missing_then_feat_broken_ghk_scn_no_then',
          'qa_ghk_outline_empty_rows_feat_broken_ghk_scn_outline_mismatch',
          'qa_ghk_outline_unresolved_feat_broken_ghk_scn_outline_mismatch',
          'qa_ghk_outline_unused_col_feat_broken_ghk_scn_outline_mismatch',
        ]),
      );

      // 8 erreurs COH-QA-GHK-002 : moduleId & personaId sur FEAT-090 +
      // EXF, UC, RG, JRN, SCR, FIX introuvables sur SCN-091.
      expect(ghkRefIssues, hasLength(8));
      expect(
        ghkRefIssues.every((i) => i.severity == CoherenceSeverity.error),
        isTrue,
      );
    });

    test('détecte les assertions TDD vides, l’absence de expectedErrorMessage sur rejectsWithError et les références TDD cassées (COH-QA-TDD-001)', () {
      final base = buildCoherentFullProject();
      final mutated = base.copyWith(
        qaSpec: base.qaSpec.copyWith(
          tddSuites: [
            ...base.qaSpec.tddSuites,
            TddTestSuiteSpec(
              id: 'tdd_empty',
              code: 'TDD-090',
              name: 'Suite TDD vide',
              targetObjectId: 'obj_fantome',
              moduleId: 'mod_fantome',
              cases: const <TddTestCaseSpec>[],
            ),
            TddTestSuiteSpec(
              id: 'tdd_broken_cases',
              code: 'TDD-091',
              name: 'Suite TDD avec cas incomplets',
              targetObjectId: 'obj_commande',
              moduleId: 'mod_cmd',
              cases: [
                TddTestCaseSpec(
                  id: 'tc_missing_act_and_assert',
                  code: 'TC-090',
                  order: 1,
                  title: 'Cas nominal sans Act ni Assert',
                  act: '',
                  outcomeKind: TddExpectedOutcomeKind.returnsValue,
                  assertExpected: '',
                  expectedErrorMessage: '',
                ),
                TddTestCaseSpec(
                  id: 'tc_reject_without_error_msg',
                  code: 'TC-091',
                  order: 2,
                  title: 'Cas de rejet muet et références invalides',
                  act: 'validator.validate(cmd)',
                  outcomeKind: TddExpectedOutcomeKind.rejectsWithError,
                  assertExpected: '',
                  expectedErrorMessage: '',
                  fixtureId: 'FIX-404',
                  businessRuleIds: const ['RG-404'],
                  requirementIds: const ['EXF-404'],
                  screenIds: const ['SCR-404'],
                ),
              ],
            ),
          ],
        ),
      );

      final issues = QaCoherenceAnalyzer.analyze(mutated);
      final tddIssues = issues
          .where((i) => i.code == 'COH-QA-TDD-001')
          .toList();

      // 10 anomalies COH-QA-TDD-001 :
      // - 1 warning suite vide (TDD-090)
      // - 2 erreurs sur TDD-090 (targetObjectId + moduleId inconnus)
      // - 2 erreurs sur TC-090 (act manquant + assertion manquante)
      // - 1 erreur sur TC-091 (rejectsWithError sans expectedErrorMessage ni assertExpected)
      // - 4 erreurs de références cassées sur TC-091 (FIX-404, RG-404, EXF-404, SCR-404)
      expect(tddIssues, hasLength(10));
      expect(
        tddIssues.where((i) => i.severity == CoherenceSeverity.warning),
        hasLength(1),
      );
      expect(
        tddIssues.where((i) => i.severity == CoherenceSeverity.error),
        hasLength(9),
      );

      final rejectIssue = tddIssues.firstWhere(
        (i) =>
            i.id ==
            'qa_tdd_empty_assert_tdd_broken_cases_tc_reject_without_error_msg',
      );
      expect(rejectIssue.title, contains('Erreur attendue manquante'));
      expect(rejectIssue.description, contains('rejectsWithError'));
    });

    test('détecte les exigences Must, cas d’usage, règles actives RG-xxx, parcours UX et écrans UX non couverts (COH-QA-COV-001)', () {
      final base = buildCoherentFullProject();
      final uncovered = base.copyWith(
        cahierDesCharges: base.cahierDesCharges.copyWith(
          functionalRequirements: [
            ...base.cahierDesCharges.functionalRequirements,
            FunctionalRequirement(
              id: 'req_must_uncov',
              code: 'EXF-003',
              title: 'Signature électronique obligatoire',
              moduleId: 'mod_cmd',
              priority: RequirementPriority.must,
              actorIds: const ['p_acheteur'],
            ),
            FunctionalRequirement(
              id: 'req_could_ignored',
              code: 'EXF-004',
              title: 'Thème saisonnier optionnel',
              moduleId: 'mod_cmd',
              priority: RequirementPriority.could,
              actorIds: const ['p_acheteur'],
            ),
          ],
          useCases: [
            ...base.cahierDesCharges.useCases,
            UseCaseSpec(
              id: 'uc_uncov',
              title: 'Annuler une commande litigieuse',
              actorId: 'p_acheteur',
            ),
          ],
        ),
        businessRules: [
          ...base.businessRules,
          BusinessRuleSpec(
            id: 'rg_active_uncov',
            code: 'RG-003',
            title: 'Double signature au-delà de 25000 EUR',
            category: BusinessRuleCategory.permission,
            targetObjectIds: const ['obj_commande'],
            active: true,
          ),
          BusinessRuleSpec(
            id: 'rg_inactive_ignored',
            code: 'RG-004',
            title: 'Ancienne règle désactivée',
            category: BusinessRuleCategory.validation,
            targetObjectIds: const ['obj_commande'],
            active: false,
          ),
        ],
        uxSpec: base.uxSpec.copyWith(
          journeys: [
            ...base.uxSpec.journeys,
            UxJourneySpec(
              id: 'jrn_uncov',
              code: 'JRN-002',
              name: 'Traitement d’un litige fournisseur',
              personaId: 'p_acheteur',
            ),
          ],
          screens: [
            ...base.uxSpec.screens,
            UxScreenSpec(
              id: 'scr_uncov',
              code: 'SCR-003',
              name: 'Console des litiges',
              routeId: 'route_commandes',
              pattern: UxScreenPattern.dashboard,
              states: UxScreenStatesSpec(emptyStateTitle: 'Aucun litige'),
            ),
          ],
        ),
      );

      final issues = QaCoherenceAnalyzer.analyze(uncovered);
      final covIssues = issues
          .where((i) => i.code == 'COH-QA-COV-001')
          .toList();

      expect(covIssues, hasLength(5));
      expect(
        covIssues.every(
          (i) =>
              i.severity == CoherenceSeverity.warning &&
              i.stage == QaForgeStage.qaReviewExport,
        ),
        isTrue,
      );
      expect(
        covIssues.map((i) => i.targetRef).toSet(),
        equals(<String>{'EXF-003', 'uc_uncov', 'RG-003', 'JRN-002', 'SCR-003'}),
      );
      // EXF-004 (Could) et RG-004 (inactive) ne génèrent pas de faux positifs.
      expect(covIssues.any((i) => i.targetRef == 'EXF-004'), isFalse);
      expect(covIssues.any((i) => i.targetRef == 'RG-004'), isFalse);
    });

    test('détecte les termes proscrits et dépréciés du CompanyGlossary dans les features Gherkin et suites TDD (COH-QA-LEX-001)', () {
      final base = buildCoherentFullProject();
      final glossary = buildSampleGlossary();
      final baseFeature = base.qaSpec.features.single;
      final baseSuite = base.qaSpec.tddSuites.single;

      final withForbiddenTerms = base.copyWith(
        qaSpec: base.qaSpec.copyWith(
          features: [
            baseFeature.copyWith(
              title: 'Gestion des devis papiers fournisseurs',
              backgroundSteps: [
                baseFeature.backgroundSteps.first.copyWith(
                  text: 'que le canal Télécopie client est désactivé',
                ),
              ],
              scenarios: [
                baseFeature.scenarios.first.copyWith(
                  title: 'Réception d’un bon volant en agence',
                  steps: [
                    baseFeature.scenarios.first.steps.first.copyWith(
                      text: 'un devis papier transmis par le fournisseur',
                    ),
                    ...baseFeature.scenarios.first.steps.skip(1),
                  ],
                ),
                ...baseFeature.scenarios.skip(1),
              ],
            ),
          ],
          tddSuites: [
            baseSuite.copyWith(
              name: 'Contrôle des Télécopie client reçues',
              cases: [
                baseSuite.cases.first.copyWith(
                  title: 'Rejette tout bon volant non référencé',
                ),
                ...baseSuite.cases.skip(1),
              ],
            ),
          ],
        ),
      );

      final issues = QaCoherenceAnalyzer.analyze(
        withForbiddenTerms,
        companyGlossary: glossary,
      );
      final lexIssues = issues
          .where((i) => i.code == 'COH-QA-LEX-001')
          .toList();

      expect(lexIssues, hasLength(6));
      expect(
        lexIssues.every((i) => i.severity == CoherenceSeverity.warning),
        isTrue,
      );
      expect(lexIssues.any((i) => i.title.contains('Terme proscrit')), isTrue);
      expect(lexIssues.any((i) => i.title.contains('Terme déprécié')), isTrue);
      expect(
        lexIssues.map((i) => i.targetRef).toSet(),
        equals(<String>{
          'FEAT-001',
          'feat_validation_cmd.bg_1',
          'SCN-001',
          'scn_val_nominale.st_1',
          'TDD-001',
          'TDD-001.TC-001',
        }),
      );
    });
  });

  group('GherkinFeatureExporter', () {
    test('exporte un fichier .feature valide en français (# language: fr, Fonctionnalité:, Contexte:, Scénario:, Plan du Scénario:, Étant donné / Quand / Alors, table Exemples alignée)', () {
      final project = buildCoherentFullProject();
      final feature = project.qaSpec.features.single;

      final frText = GherkinFeatureExporter.exportFeature(
        feature,
        language: GherkinKeywordLanguage.fr,
      );

      expect(frText, startsWith('# language: fr\n\n'));
      expect(frText, contains('@feat-001 @commandes @smoke'));
      expect(
        frText,
        contains(
          'Fonctionnalité: Validation et contrôle plafond des commandes B2B',
        ),
      );
      expect(frText, contains('  En tant qu’Acheteur B2B'));
      expect(frText, contains('  Contexte:'));
      expect(
        frText,
        contains(
          '    Étant donné que l’acheteur habilité est connecté au portefeuille des commandes',
        ),
      );
      expect(frText, contains('  @scn-001 @nominal'));
      expect(
        frText,
        contains('  Scénario: Validation nominale d’une commande B2B conforme'),
      );
      expect(
        frText,
        contains('    Quand l’acheteur confirme la validation de la commande'),
      );
      expect(
        frText,
        contains('    Alors la commande passe au statut "validee"'),
      );
      expect(
        frText,
        contains('    Et une notification de confirmation est affichée'),
      );
      expect(
        frText,
        contains('    Mais aucune alerte de dépassement n’est émise'),
      );
      expect(
        frText,
        contains('      """\n      {"statut": "validee"}\n      """'),
      );
      expect(
        frText,
        contains(
          '  Plan du Scénario: Contrôle paramétré du plafond HT à la validation',
        ),
      );
      expect(frText, contains('    Exemples:'));

      // Vérifie l'alignement strict des tubes '|' et l'échappement de '|' interne dans Exemples.
      final examplePipeLines = frText
          .split('\n')
          .where((line) => line.startsWith('      | '))
          .toList();
      // 2 lignes pour la dataTable du scénario 1 + 4 lignes (en-tête + 3 lignes) pour Exemples.
      expect(examplePipeLines, hasLength(6));
      final outlineExampleLines = examplePipeLines.sublist(2);
      final expectedLineLength = outlineExampleLines.first.length;
      for (final line in outlineExampleLines) {
        expect(line.length, expectedLineLength);
      }
      expect(outlineExampleLines.last, contains(r'rejetee \| hors plafond'));
    });

    test('exporte un fichier .feature valide en anglais (# language: en, Feature:, Scenario Outline:, Given / When / Then, Examples:) et déduplique les noms de fichiers', () {
      final project = buildCoherentFullProject();
      final feature = project.qaSpec.features.single;

      final enText = GherkinFeatureExporter.exportFeature(
        feature,
        language: GherkinKeywordLanguage.en,
      );

      expect(enText, startsWith('# language: en\n\n'));
      expect(
        enText,
        contains('Feature: Validation et contrôle plafond des commandes B2B'),
      );
      expect(enText, contains('  Background:'));
      expect(
        enText,
        contains(
          '    Given que l’acheteur habilité est connecté au portefeuille des commandes',
        ),
      );
      expect(
        enText,
        contains('  Scenario: Validation nominale d’une commande B2B conforme'),
      );
      expect(
        enText,
        contains('    When l’acheteur confirme la validation de la commande'),
      );
      expect(
        enText,
        contains('    Then la commande passe au statut "validee"'),
      );
      expect(
        enText,
        contains('    And une notification de confirmation est affichée'),
      );
      expect(
        enText,
        contains('    But aucune alerte de dépassement n’est émise'),
      );
      expect(
        enText,
        contains(
          '  Scenario Outline: Contrôle paramétré du plafond HT à la validation',
        ),
      );
      expect(enText, contains('    Examples:'));

      // Vérifie la déduplication déterministe des noms de fichiers .feature et l'aperçu combiné.
      final duplicatedFeaturesProject = project.copyWith(
        qaSpec: project.qaSpec.copyWith(
          gherkinLanguage: GherkinKeywordLanguage.en,
          features: [
            feature,
            feature.copyWith(id: 'feat_validation_cmd_bis'),
          ],
        ),
      );
      final exportedMap = GherkinFeatureExporter.exportAllFeatures(
        duplicatedFeaturesProject,
      );
      expect(exportedMap, hasLength(2));
      expect(
        exportedMap.keys.every((name) => name.endsWith('.feature')),
        isTrue,
      );
      expect(
        exportedMap.values.every(
          (content) => content.startsWith('# language: en\n'),
        ),
        isTrue,
      );

      final combinedPreview = GherkinFeatureExporter.exportCombinedPreview(
        duplicatedFeaturesProject,
      );
      for (final fileName in exportedMap.keys) {
        expect(combinedPreview, contains('# ═══ features/$fileName ═══'));
      }
    });
  });

  group('QaMarkdownExporter, QaTddPromptExporter, QaAutoSeeder & QaDirectoryExporter', () {
    test('QaAutoSeeder génère des fixtures, features Gherkin et suites TDD valides rendant un projet initialement non couvert 100 % cohérent', () {
      final uncovered = buildUncoveredFullProject();
      expect(uncovered.qaSpec.fixtures, isEmpty);
      expect(uncovered.qaSpec.features, isEmpty);
      expect(uncovered.qaSpec.tddSuites, isEmpty);
      expect(QaCoherenceAnalyzer.analyze(uncovered), isNotEmpty);

      // 1. Auto-seed des fixtures depuis les objets métiers & contraintes JSON Schema.
      final seededFixtures = QaAutoSeeder.seedFixturesFromSchema(uncovered);
      // 2 objets métiers -> 2 fixtures (nominal + invalid/boundary) chacun = 4 fixtures.
      expect(seededFixtures, hasLength(4));
      expect(seededFixtures.where((f) => f.expectedValid), hasLength(2));
      expect(seededFixtures.where((f) => !f.expectedValid), hasLength(2));

      final withFixtures = uncovered.copyWith(
        qaSpec: uncovered.qaSpec.copyWith(fixtures: seededFixtures),
      );
      expect(withFixtures.validate, returnsNormally);
      // Idempotence lorsque tous les objets métiers sont déjà couverts.
      expect(QaAutoSeeder.seedFixturesFromSchema(withFixtures), isEmpty);

      // 2. Auto-seed des fonctionnalités Gherkin depuis la spec Métier + UX.
      final seededFeatures = QaAutoSeeder.seedFeaturesFromSpecAndUx(
        withFixtures,
      );
      expect(seededFeatures, isNotEmpty);
      for (final feature in seededFeatures) {
        expect(feature.scenarios, isNotEmpty);
        for (final sc in feature.scenarios) {
          expect(
            sc.steps.any((s) => s.keyword == GherkinStepKeyword.then),
            isTrue,
          );
        }
      }

      final withFeatures = withFixtures.copyWith(
        qaSpec: withFixtures.qaSpec.copyWith(features: seededFeatures),
      );
      expect(withFeatures.validate, returnsNormally);
      expect(QaAutoSeeder.seedFeaturesFromSpecAndUx(withFeatures), isEmpty);

      // 3. Auto-seed des suites unitaires TDD depuis les règles actives RG-xxx.
      final seededSuites = QaAutoSeeder.seedTddSuitesFromRules(withFeatures);
      expect(seededSuites, isNotEmpty);
      final totalCases = seededSuites.fold<int>(
        0,
        (sum, s) => sum + s.cases.length,
      );
      // 2 règles actives (RG-001 et RG-002) -> 2 cas (nominal + rejet) par règle = 4 cas.
      expect(totalCases, 4);

      final fullySeeded = withFeatures.copyWith(
        qaSpec: withFeatures.qaSpec.copyWith(tddSuites: seededSuites),
      );
      expect(fullySeeded.validate, returnsNormally);
      expect(QaAutoSeeder.seedTddSuitesFromRules(fullySeeded), isEmpty);

      // Le projet entièrement amorcé par QaAutoSeeder atteint 0 anomalie de cohérence 360°.
      expect(QaCoherenceAnalyzer.analyze(fullySeeded), isEmpty);
    });

    test('QaMarkdownExporter.export et QaTddPromptExporter.export produisent la documentation BDD/TDD complète et la feuille de route Red → Green → Refactor', () {
      final project = buildCoherentFullProject();

      final qaMd = QaMarkdownExporter.export(project);
      expect(
        qaMd,
        contains(
          '# Cahier de Recette BDD / Gherkin & Stratégie TDD — B2B Order QA Studio',
        ),
      );
      expect(qaMd, contains('## 1. Synthèse & Métriques de couverture'));
      expect(
        qaMd,
        contains('| **Objets métiers dotés de fixtures** | 2 / 2 | 100 % |'),
      );
      expect(
        qaMd,
        contains(
          '| **Exigences fonctionnelles `EXF` (Must)** | 1 / 1 | 100 % |',
        ),
      );
      expect(
        qaMd,
        contains(
          '| **Règles de gestion actives (`RG-xxx`)** | 2 / 2 | 100 % |',
        ),
      );
      expect(qaMd, contains('## 2. Jeux de Données & Cas aux Limites'));
      expect(qaMd, contains('`FIX-001`'));
      expect(qaMd, contains('`FIX-002`'));
      expect(qaMd, contains('## 3. Spécifications Exécutables Gherkin'));
      expect(qaMd, contains('```gherkin'));
      expect(qaMd, contains('## 4. Suites de Tests Unitaires & Contrats TDD'));
      expect(qaMd, contains('Progression Red → Green → Refactor (3 cas)'));
      expect(qaMd, contains('## 5. Matrice de Traçabilité 360°'));
      expect(qaMd, contains('`FEAT-001/SCN-001`'));
      expect(qaMd, contains('`TDD-001/TC-002`'));

      final tddPrompt = QaTddPromptExporter.export(project);
      expect(
        tddPrompt,
        contains(
          '# Prompt Agent IA — Implémentation ATDD / BDD & TDD — B2B Order QA Studio',
        ),
      );
      expect(
        tddPrompt,
        contains(
          '## 1. Discipline d’Exécution ATDD / BDD & Red → Green → Refactor',
        ),
      );
      expect(
        tddPrompt,
        contains(
          '## 2. Langage Omniprésent (`SpecLexicon`) & Conventions de Modélisation',
        ),
      );
      expect(
        tddPrompt,
        contains(
          '## 3. Schéma du Domaine Métier & Règles de Gestion (`RG-xxx`)',
        ),
      );
      expect(
        tddPrompt,
        contains(
          '## 4. Référentiel des Jeux de Données Exportés (`fixtures/*.json`)',
        ),
      );
      expect(
        tddPrompt,
        contains(
          '## 5. Feuille de Route TDD Ordonnée (`TDD-xxx` / `TC-xxx` : Red → Green → Refactor)',
        ),
      );
      expect(
        tddPrompt,
        contains(
          '## 6. Porte d’Acceptation Finale : Scénarios BDD (`features/*.feature`) & UX',
        ),
      );
      expect(
        tddPrompt,
        contains('`fixtures/fix-001-commande-nominale-conforme.json`'),
      );
      expect(
        tddPrompt,
        contains(
          'Expected Error** : « Montant HT supérieur au plafond autorisé (50000 EUR) »',
        ),
      );
    });

    test('QaDirectoryExporter.exportQaDirectory écrit features/*.feature, fixtures/*.json, fixtures_bundle.json, specification_bdd_tdd.md, specification_qa.json et prompt_tdd_agent.md sans aucun fichier .html', () async {
      final project = buildCoherentFullProject();
      final sep = Platform.pathSeparator;
      final tempRoot = await Directory.systemTemp.createTemp(
        'spec_forge_qa_export_dir_',
      );

      try {
        final outDir = Directory('${tempRoot.path}${sep}qa_export_out');
        await Directory('${outDir.path}${sep}features').create(recursive: true);
        await Directory('${outDir.path}${sep}fixtures').create(recursive: true);

        // Pré-dépose un ancien fichier HTML et des artefacts obsolètes pour vérifier le nettoyage.
        await File('${outDir.path}${sep}specification_bdd_tdd.html')
            .writeAsString('<html>legacy</html>', flush: true);
        await File('${outDir.path}${sep}features${sep}obsolete.feature')
            .writeAsString('# language: fr\n', flush: true);
        await File('${outDir.path}${sep}fixtures${sep}obsolete.json')
            .writeAsString('{}', flush: true);

        await QaDirectoryExporter.exportQaDirectory(project, outDir);

        // 1. Vérifie l'absence totale de tout fichier .html dans l'arborescence exportée.
        final allExportedFiles = <File>[
          await for (final entity in outDir.list(
            recursive: true,
            followLinks: false,
          ))
            if (entity is File) entity,
        ];
        expect(
          allExportedFiles.where((f) => f.path.toLowerCase().endsWith('.html')),
          isEmpty,
        );

        // 2. Vérifie features/*.feature et la purge des fichiers obsolètes.
        final expectedFeatures = GherkinFeatureExporter.exportAllFeatures(
          project,
        );
        expect(expectedFeatures, isNotEmpty);
        expect(
          await File('${outDir.path}${sep}features${sep}obsolete.feature')
              .exists(),
          isFalse,
        );
        for (final entry in expectedFeatures.entries) {
          final featureFile = File(
            '${outDir.path}${sep}features$sep${entry.key}',
          );
          expect(await featureFile.exists(), isTrue);
          expect(await featureFile.readAsString(), equals(entry.value));
        }

        // 3. Vérifie fixtures/*.json et fixtures_bundle.json.
        final expectedFixtures = QaDirectoryExporter.buildFixturesFilesMap(
          project,
        );
        expect(expectedFixtures, hasLength(3));
        expect(
          await File('${outDir.path}${sep}fixtures${sep}obsolete.json')
              .exists(),
          isFalse,
        );
        for (final entry in expectedFixtures.entries) {
          final fixtureFile = File(
            '${outDir.path}${sep}fixtures$sep${entry.key}',
          );
          expect(await fixtureFile.exists(), isTrue);
          final decoded = QaFixtureSpec.fromJson(
            jsonDecode(await fixtureFile.readAsString()),
          );
          expect(decoded.toJson(), equals(entry.value));
        }

        final bundleFile = File('${outDir.path}${sep}fixtures_bundle.json');
        expect(await bundleFile.exists(), isTrue);
        final bundleJson =
            jsonDecode(await bundleFile.readAsString()) as Map<String, Object?>;
        final bundledList = bundleJson['fixtures'] as List<Object?>;
        expect(bundledList, hasLength(3));

        // 4. Vérifie specification_bdd_tdd.md, specification_qa.json et prompt_tdd_agent.md.
        final mdFile = File('${outDir.path}${sep}specification_bdd_tdd.md');
        expect(await mdFile.exists(), isTrue);
        expect(
          await mdFile.readAsString(),
          equals(QaMarkdownExporter.export(project)),
        );

        final qaJsonFile = File('${outDir.path}${sep}specification_qa.json');
        expect(await qaJsonFile.exists(), isTrue);
        final reloadedQaSpec = QaForgeSpec.fromJson(
          jsonDecode(await qaJsonFile.readAsString()),
        );
        expect(reloadedQaSpec, equals(project.qaSpec));

        final promptFile = File('${outDir.path}${sep}prompt_tdd_agent.md');
        expect(await promptFile.exists(), isTrue);
        expect(
          await promptFile.readAsString(),
          equals(QaTddPromptExporter.export(project)),
        );
      } finally {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    });
  });
}
