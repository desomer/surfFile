import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecInitiative, SpecFeatureSpec & projection SpecForgeProject', () {
    test('partage Lexique et ModelPreferences au niveau Projet tout en isolant les 4 Wizards par Feature', () {
      final feat1 =
          SpecFeatureSpec.create(
            id: 'feat_devis',
            code: 'FEAT-01',
            name: 'Gestion des devis',
            description: 'Création et validation des devis clients',
            targetRelease: 'MVP',
          ).copyWith(
            businessObjects: [
              BusinessObjectSpec(
                id: 'obj_devis',
                name: 'Devis',
                technicalName: 'Quote',
              ),
            ],
            uxSpec: UxForgeSpec(
              screens: [
                UxScreenSpec(
                  id: 'scr_devis',
                  code: 'SCR-01',
                  name: 'Écran Devis',
                ),
              ],
            ),
          );

      final feat2 =
          SpecFeatureSpec.create(
            id: 'feat_factures',
            code: 'FEAT-02',
            name: 'Facturation & Avoirs',
            description: 'Émission des factures et avoirs',
            targetRelease: 'Lot 2',
            priority: RequirementPriority.should,
          ).copyWith(
            currentStage: SpecForgeStage.businessRules,
            businessRules: [
              BusinessRuleSpec(
                id: 'rg_1',
                code: 'RG-001',
                title: 'Numérotation séquentielle sans trou',
              ),
            ],
          );

      final init = SpecInitiative.create(
        id: 'init_commercial',
        code: 'INIT-01',
        name: 'Cycle Commercial',
        features: [feat1, feat2],
      );

      var project =
          SpecForgeProject.fromIdea(
            id: 'proj_erp',
            name: 'ERP Artisans',
            idea: 'Suite commerciale pour artisans',
          ).copyWith(
            lexicon: SpecLexicon(
              terms: [
                LexiconTerm(
                  id: 't_client',
                  term: 'Client',
                  definition: 'Donneur d’ordre facturé',
                ),
              ],
            ),
            initiatives: [init],
            activeFeatureId: 'feat_devis',
          );

      // Sur feat_devis : démarre par défaut sur Cadrage & Acteurs, voit Quote, 0 règle, 1 écran UX et le lexique partagé.
      expect(project.activeFeature.id, 'feat_devis');
      expect(project.currentStage, SpecForgeStage.vision);
      expect(SpecForgeStage.vision.stepNumber, 1);
      expect(SpecForgeStage.lexicon.stepNumber, 2);
      expect(project.businessObjects.single.technicalName, 'Quote');
      expect(project.businessRules, isEmpty);
      expect(project.uxSpec.screens.length, 1);
      expect(project.lexicon.terms.single.term, 'Client');

      final complementPrompt = SpecPromptBuilder.buildLexiconComplementPrompt(
        project,
      );
      expect(complementPrompt, contains('FEAT-01 · Gestion des devis'));
      expect(complementPrompt, contains('1 terme(s)'));

      // Bascule sur feat_factures : voit RG-001, 0 objet, 0 écran UX mais toujours le même lexique partagé.
      project = project.selectFeature('feat_factures');
      expect(project.activeFeature.id, 'feat_factures');
      expect(project.currentStage, SpecForgeStage.businessRules);
      expect(project.businessObjects, isEmpty);
      expect(project.businessRules.single.code, 'RG-001');
      expect(project.uxSpec.screens, isEmpty);
      expect(project.lexicon.terms.single.term, 'Client');

      // Enrichir le lexique depuis feat_factures reste visible après retour sur feat_devis.
      final updatedLexicon = project.lexicon.copyWith(
        terms: [
          ...project.lexicon.terms,
          LexiconTerm(
            id: 't_avoir',
            term: 'Avoir',
            definition: 'Note de crédit',
          ),
        ],
      );
      final lexiconMsg = SpecChatMessage(
        id: 'm_lex',
        isUser: true,
        text: 'Ajoute Avoir',
      );
      project = project
          .copyWith(
            lexicon: updatedLexicon,
            stageStates: {
              ...project.stageStates,
              SpecForgeStage.lexicon: project
                  .stageStateFor(SpecForgeStage.lexicon)
                  .copyWith(
                    status: SpecStageStatus.validated,
                    messages: [lexiconMsg],
                  ),
              SpecForgeStage.businessRules: project
                  .stageStateFor(SpecForgeStage.businessRules)
                  .copyWith(status: SpecStageStatus.validated),
            },
          )
          .selectFeature('feat_devis');

      expect(project.lexicon.terms.length, 2);
      expect(
        project.stageStateFor(SpecForgeStage.lexicon).status,
        SpecStageStatus.validated,
      );
      expect(
        project.stageStateFor(SpecForgeStage.lexicon).messages.single.text,
        'Ajoute Avoir',
      );
      // L'étape 7 (propre à la feature) est restée non démarrée sur feat_devis.
      expect(
        project.stageStateFor(SpecForgeStage.businessRules).status,
        SpecStageStatus.notStarted,
      );

      // Sérialisation JSON complète aller-retour et contexte compact IA.
      final roundTripped = SpecForgeProject.fromJson(project.toJson());
      expect(roundTripped, equals(project));

      final contextJson = project.toCompactContextJson(SpecForgeStage.vision);
      expect(contextJson['activeInitiative'], isA<Map<String, Object?>>());
      expect((contextJson['activeFeature'] as Map)['id'], equals('feat_devis'));
    });

    test(
      'rejette les identifiants de features dupliqués entre initiatives',
      () {
        final f1 = SpecFeatureSpec.create(
          id: 'dup_feat',
          code: 'F1',
          name: 'A',
        );
        final f2 = SpecFeatureSpec.create(
          id: 'dup_feat',
          code: 'F2',
          name: 'B',
        );
        expect(
          () => SpecForgeProject.fromIdea(idea: 'Test')
              .copyWith(
                initiatives: [
                  SpecInitiative.create(
                    id: 'i1',
                    code: 'I1',
                    name: 'Init 1',
                    features: [f1],
                  ),
                  SpecInitiative.create(
                    id: 'i2',
                    code: 'I2',
                    name: 'Init 2',
                    features: [f2],
                  ),
                ],
              )
              .validate(),
          throwsFormatException,
        );
      },
    );
  });

  group('PortfolioSlicingAiAgent.applyPatch', () {
    test('remplace la feature placeholder vide par le découpage IA puis préserve les livrables Wizards lors d’un second patch', () {
      final initial = SpecForgeProject.fromIdea(
        id: 'proj_fleet',
        name: 'FleetApp',
        idea: 'Gestion de flotte automobile d’entreprise',
      );
      expect(initial.hasSingleDefaultFeature, isTrue);

      final firstApplied = PortfolioSlicingAiAgent.applyPatch(initial, {
        'replaceDefaultPlaceholder': true,
        'activeFeatureId': 'feat_resa',
        'initiatives': [
          {
            'id': 'init_socle',
            'code': 'INIT-01',
            'name': 'Socle Parc & Réservations',
            'description': 'Digitalisation du parc et des prêts',
            'priority': 'must',
            'features': [
              {
                'id': 'feat_parc',
                'code': 'FEAT-01',
                'name': 'Référentiel véhicules',
                'description': 'Fiches véhicules et immatriculations.',
                'targetRelease': 'MVP',
                'priority': 'must',
              },
              {
                'id': 'feat_resa',
                'code': 'FEAT-02',
                'name': 'Réservation collaborateur',
                'description': 'Demande de véhicule et relevé kilométrique.',
                'targetRelease': 'MVP',
                'priority': 'must',
              },
            ],
          },
        ],
      });

      final sliced = firstApplied.project;
      expect(sliced.initiatives.length, 1);
      expect(sliced.totalFeatureCount, 2);
      expect(sliced.activeFeatureId, 'feat_resa');
      expect(
        sliced.activeFeature.vision.ideaSummary,
        'Demande de véhicule et relevé kilométrique.',
      );

      // Simulation d'un travail dans le Wizard Spec sur feat_resa (ajout d'un objet métier).
      final withDeliverable = sliced.copyWith(
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_booking',
            name: 'Réservation',
            technicalName: 'VehicleBooking',
          ),
        ],
      );

      // Un second patch IA affine le titre de feat_resa et ajoute INIT-02 sans écraser VehicleBooking.
      final secondApplied = PortfolioSlicingAiAgent.applyPatch(
        withDeliverable,
        {
          'initiatives': [
            {
              'id': 'init_socle',
              'features': [
                {
                  'id': 'feat_resa',
                  'name': 'Réservation & Check-in/out',
                  'targetRelease': 'MVP Sprint 1',
                },
              ],
            },
            {
              'id': 'init_sinistres',
              'code': 'INIT-02',
              'name': 'Sinistres & Refacturation',
              'priority': 'should',
              'features': [
                {
                  'id': 'feat_sinistres',
                  'code': 'FEAT-03',
                  'name': 'Déclaration de sinistre',
                  'priority': 'should',
                },
              ],
            },
          ],
        },
      );

      final refined = secondApplied.project;
      expect(refined.initiatives.length, 2);
      expect(refined.totalFeatureCount, 3);
      final updatedResa = refined.featureById('feat_resa')!;
      expect(updatedResa.name, 'Réservation & Check-in/out');
      expect(updatedResa.targetRelease, 'MVP Sprint 1');
      expect(
        updatedResa.businessObjects.single.technicalName,
        'VehicleBooking',
      );
    });

    test(
      'Étapes optionnelles par feature (Event Storming & Example Mapping) : normalisation, navigation, cohérence et export',
      () {
        expect(SpecForgeStage.eventStorming.isOptional, isTrue);
        expect(SpecForgeStage.exampleMapping.isOptional, isTrue);
        expect(SpecForgeStage.businessObjects.isOptional, isFalse);
        expect(
          SpecForgeStage.optionalStages,
          const [SpecForgeStage.eventStorming, SpecForgeStage.exampleMapping],
        );

        // Les étapes obligatoires sont ignorées lors de la normalisation de disabledSpecStages,
        // et currentStage bascule sur l'étape active précédente si elle est désactivée.
        final feat = SpecFeatureSpec(
          id: 'feat_light',
          code: 'FEAT-01',
          name: 'Feature légère',
          currentStage: SpecForgeStage.eventStorming,
          disabledSpecStages: const {
            SpecForgeStage.vision, // obligatoire -> ignorée
            SpecForgeStage.eventStorming,
            SpecForgeStage.exampleMapping,
          },
          exampleMappings: [
            ExampleMapStory(
              id: 'em_1',
              code: 'EM-01',
              title: 'Ancienne story conservée',
              questions: const [
                ExampleMapQuestion(id: 'q1', question: 'Question ouverte ?'),
              ],
            ),
          ],
        );

        expect(
          feat.disabledSpecStages,
          const {SpecForgeStage.eventStorming, SpecForgeStage.exampleMapping},
        );
        expect(feat.currentStage, SpecForgeStage.specifications);
        expect(feat.enabledSpecStages, const [
          SpecForgeStage.vision,
          SpecForgeStage.lexicon,
          SpecForgeStage.specifications,
          SpecForgeStage.businessObjects,
          SpecForgeStage.businessRules,
          SpecForgeStage.reviewExport,
        ]);
        expect(feat.stepNumberFor(SpecForgeStage.businessObjects), 4);
        expect(feat.stepNumberFor(SpecForgeStage.businessRules), 5);
        expect(feat.stepNumberFor(SpecForgeStage.reviewExport), 6);
        expect(
          feat.nextEnabledStage(SpecForgeStage.specifications),
          SpecForgeStage.businessObjects,
        );
        expect(
          feat.nextEnabledStage(SpecForgeStage.businessObjects),
          SpecForgeStage.businessRules,
        );
        expect(
          feat.previousEnabledStage(SpecForgeStage.businessRules),
          SpecForgeStage.businessObjects,
        );
        // Les données existantes sont préservées mais ne font pas échouer la cohérence ni l'export.
        expect(feat.exampleMappings, hasLength(1));

        final now = DateTime.utc(2026, 6, 1);
        final project = SpecForgeProject(
          id: 'proj_opt',
          name: 'OptSpec',
          initialIdea: 'Idée test',
          createdAt: now,
          updatedAt: now,
          initiatives: [
            SpecInitiative(
              id: 'init_1',
              code: 'INIT-01',
              name: 'Init 1',
              features: [feat],
            ),
          ],
          activeFeatureId: 'feat_light',
        );

        // moveToStage ignore une étape désactivée.
        expect(
          project.moveToStage(SpecForgeStage.eventStorming).currentStage,
          SpecForgeStage.specifications,
        );

        // SpecCoherenceAnalyzer ignore les contrôles des étapes désactivées.
        final issues = SpecCoherenceAnalyzer.analyze(project);
        expect(
          issues.any((i) => i.stage == SpecForgeStage.exampleMapping),
          isFalse,
        );
        expect(
          issues.any((i) => i.stage == SpecForgeStage.eventStorming),
          isFalse,
        );

        // SpecMarkdownExporter omet les sections désactivées.
        final markdown = SpecMarkdownExporter.export(project);
        expect(markdown, isNot(contains('## 4. Event Storming')));
        expect(markdown, isNot(contains('Example Mapping')));

        // Aller-retour JSON préserve disabledSpecStages.
        final roundTripped = SpecForgeProject.fromJson(project.toJson());
        expect(
          roundTripped.activeFeature.disabledSpecStages,
          const {SpecForgeStage.eventStorming, SpecForgeStage.exampleMapping},
        );
      },
    );
  });
}
