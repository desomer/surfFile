import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('Modèles Estimation de coût IT, PERT, TCO, AutoSeeder & Exports', () {
    test('CostForgeSpec.empty garde hasContent=false et préserve la rétrocompatibilité JSON', () {
      final project = SpecForgeProject.fromIdea(
        idea: 'Plateforme SaaS de facturation électronique',
        name: 'FacturPro',
        id: 'proj_facturpro',
      );

      expect(project.costSpec, equals(CostForgeSpec.empty));
      expect(project.costSpec.hasContent, isFalse);

      final json = project.toJson();
      expect(json.containsKey('costSpec'), isFalse);

      final reloaded = SpecForgeProject.fromJson(json);
      expect(reloaded.costSpec, equals(CostForgeSpec.empty));
    });

    test('CostWbsItemSpec supporte T-shirt PERT 3 points et charge fixe directe en jours/homme', () {
      final pertItem = CostWbsItemSpec(
        id: 'wbs_1',
        code: 'WBS-001',
        title: 'Moteur de calcul TVA',
        optimisticDays: 2.0,
        mostLikelyDays: 5.0,
        pessimisticDays: 14.0,
      );
      expect(pertItem.isDirectDays, isFalse);
      expect(pertItem.expectedDays, closeTo(6.0, 1e-6));
      expect(pertItem.stdDevDays, closeTo(2.0, 1e-6));

      final directItem = pertItem.withDirectDays(4.5);
      expect(directItem.isDirectDays, isTrue);
      expect(directItem.tshirtSize, CostTShirtSize.custom);
      expect(directItem.expectedDays, closeTo(4.5, 1e-6));
      expect(directItem.stdDevDays, closeTo(0.0, 1e-6));

      final fromShorthand = CostWbsItemSpec.fromJson(const <String, Object?>{
        'id': 'wbs_2',
        'code': 'WBS-002',
        'title': 'Connecteur bancaire',
        'days': 7.5,
      });
      expect(fromShorthand.isDirectDays, isTrue);
      expect(fromShorthand.expectedDays, closeTo(7.5, 1e-6));
    });

    test('CostCalculator calcule les lots MoSCoW, le gain IA, le Run multi-années et le TCO 1/3/5 ans', () {
      final spec = CostForgeSpec(
        currency: CostCurrency.eur,
        deliveryMode: CostDeliveryMode.inHouse,
        transverseRatios: const TransverseRatioSettings(
          projectManagementPct: 10.0,
          architectureDevOpsPct: 10.0,
          transverseQaPct: 0.0,
          contingencyPct: 10.0,
        ),
        aiProductivity: const AiProductivitySettings(
          enabled: true,
          backendGainPct: 25.0,
          pmSpecsGainPct: 0.0,
          devSecOpsGainPct: 0.0,
        ),
        wbsItems: [
          CostWbsItemSpec(
            id: 'wbs_must',
            code: 'WBS-001',
            title: 'API Commandes',
            discipline: CostDiscipline.backend,
            priority: RequirementPriority.must,
            profileId: 'prof_back',
          ).withDirectDays(20.0),
          CostWbsItemSpec(
            id: 'wbs_should',
            code: 'WBS-002',
            title: 'Reporting avancé',
            discipline: CostDiscipline.backend,
            priority: RequirementPriority.should,
            profileId: 'prof_back',
          ).withDirectDays(12.0),
        ],
        runItems: [
          const CostRunItemSpec(
            id: 'run_cloud',
            code: 'RUN-001',
            name: 'Cluster Kubernetes Prod',
            category: CostRunCategory.cloudInfra,
            environment: CostEnvironmentScope.prod,
            billingCycle: CostBillingCycle.monthly,
            unitCost: 500.0,
            quantity: 1.0,
            annualGrowthPct: 10.0,
          ),
        ],
        riskItems: [
          CostRiskItemSpec(
            id: 'rsk_1',
            code: 'RSK-001',
            title: 'Latence API partenaire',
            probabilityPct: 50.0,
            impactDays: 4.0,
            fixedCostImpact: 1000.0,
            profileId: 'prof_back',
          ),
        ],
      );

      final summary = CostCalculator.compute(spec);
      expect(summary.mvpLot.itemCount, 1);
      expect(summary.v1Lot.itemCount, 2);
      expect(summary.fullLot.classicTotalDays, greaterThan(summary.fullLot.aiTotalDays));
      expect(summary.fullLot.aiSavedDays, greaterThan(0));
      expect(summary.fullLot.aiSavedCost, greaterThan(0));
      expect(summary.monthlyRunYear1, closeTo(500.0, 1e-6));
      expect(summary.yearlyRunYear1, closeTo(6000.0, 1e-6));
      expect(summary.yearlyRunYear2, closeTo(6600.0, 1e-6));
      expect(summary.riskEmvDays, closeTo(2.0, 1e-6));
      expect(summary.tco3Years, greaterThan(summary.tco1Year));
      expect(summary.tco5Years, greaterThan(summary.tco3Years));
    });

    test('CostAutoSeeder, CostPatchApplier et CostMarkdownExporter/CostCsvExporter fonctionnent de bout en bout', () {
      var project = SpecForgeProject.fromIdea(
        idea: 'Portail logistique B2B avec IA prédictive',
        name: 'LogiPulse',
        id: 'proj_logipulse',
      );
      project = project.copyWith(
        cahierDesCharges: SpecCahierDesCharges(
          modules: const [SpecModule(id: 'mod_exp', name: 'Expéditions')],
          functionalRequirements: [
            FunctionalRequirement(
              id: 'ef_1',
              code: 'EF-001',
              title: 'Planifier une tournée',
              moduleId: 'mod_exp',
              priority: RequirementPriority.must,
            ),
            FunctionalRequirement(
              id: 'ef_2',
              code: 'EF-002',
              title: 'Suivre les colis en temps réel',
              moduleId: 'mod_exp',
              priority: RequirementPriority.should,
            ),
          ],
        ),
        eventStorming: EventStormingSpec(
          documents: [
            EventStormDocument(
              id: 'expedition',
              meta: const EventStormMeta(
                domain: 'Logistique',
                boundedContext: 'Expédition',
                date: '2026-11-24',
              ),
              catalog: EventStormCatalog(
                aggregates: const [
                  EventStormCatalogItem(id: 'AGG-COLIS', name: 'Colis'),
                ],
              ),
              flow: [
                EventStormStep(
                  step: 1,
                  command: EventStormCommand(name: 'Expédier le colis'),
                  aggregate: 'AGG-COLIS',
                  domainEvent: EventStormDomainEvent(
                    id: 'EVT-01',
                    name: 'Colis expédié',
                  ),
                  hotspots: const [
                    EventStormHotspot(
                      id: 'HS-01',
                      question: 'Quota API transporteur',
                      severity: EventStormHotspotSeverity.high,
                      owner: 'Architecte',
                      status: EventStormHotspotStatus.open,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final seedRes = CostAutoSeeder.seedFromProject(
        project,
        enterpriseRateCard: EnterpriseRateCard.defaults,
      );
      expect(seedRes.addedWbsCount, greaterThanOrEqualTo(2));
      expect(seedRes.addedRunCount, greaterThan(0));
      expect(seedRes.addedRiskCount, greaterThanOrEqualTo(1));

      project = project.copyWith(costSpec: seedRes.spec);

      // Idempotence : un second appel ne duplique pas les éléments déjà couverts
      final secondSeed = CostAutoSeeder.seedFromProject(project);
      expect(secondSeed.addedWbsCount, 0);
      expect(secondSeed.addedRiskCount, 0);

      // Application d'un costPatch IA
      final patched = CostPatchApplier.apply(
        project,
        costPatch: const <String, Object?>{
          'currency': 'USD',
          'targetUsersCount': 2500,
          'wbsItems': <Map<String, Object?>>[
            {
              'id': 'wbs_sso',
              'code': 'WBS-099',
              'title': 'Intégration SSO SAML',
              'discipline': 'devSecOps',
              'priority': 'must',
              'tshirtSize': 'M',
              'optimisticDays': 2,
              'mostLikelyDays': 4,
              'pessimisticDays': 7,
            },
          ],
        },
      );
      expect(patched.project.costSpec.currency, CostCurrency.usd);
      expect(patched.project.costSpec.targetUsersCount, 2500);
      expect(patched.project.costSpec.findWbsItem('WBS-099'), isNotNull);

      final md = CostMarkdownExporter.export(patched.project);
      expect(md, contains('LogiPulse'));
      expect(md, contains('WBS-099'));
      expect(md, contains('TCO'));

      final csvFiles = CostCsvExporter.exportAllFiles(patched.project);
      expect(csvFiles.keys, containsAll(['cost_summary_tco.csv', 'cost_build_wbs.csv', 'cost_run_opex.csv']));
      expect(csvFiles['cost_build_wbs.csv'], contains('WBS-099'));
    });

    test('CostAutoSeeder.findUncoveredArtifacts recense les écarts avant et après amorçage', () {
      var project = SpecForgeProject.fromIdea(
        idea: 'Gestion des devis',
        name: 'DevisFlow',
        id: 'proj_devis',
      );
      project = project.copyWith(
        cahierDesCharges: SpecCahierDesCharges(
          functionalRequirements: [
            FunctionalRequirement(
              id: 'ef_1',
              code: 'EF-001',
              title: 'Créer un devis',
              priority: RequirementPriority.must,
            ),
          ],
          nonFunctionalRequirements: [
            NonFunctionalRequirement(
              id: 'enf_sec',
              code: 'ENF-001',
              title: 'Chiffrement TLS & AES-256',
              category: NonFunctionalCategory.security,
            ),
          ],
        ),
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_devis',
            name: 'Devis',
            technicalName: 'Devis',
          ),
        ],
        eventStorming: EventStormingSpec(
          documents: [
            EventStormDocument(
              id: 'ventes',
              meta: const EventStormMeta(
                domain: 'Ventes',
                boundedContext: 'Devis',
                date: '2026-11-27',
              ),
              flow: [
                EventStormStep(
                  step: 1,
                  command: EventStormCommand(name: 'Valider le devis'),
                  hotspots: const [
                    EventStormHotspot(
                      id: 'HS-01',
                      question: 'Règle de TVA intracommunautaire',
                      severity: EventStormHotspotSeverity.blocker,
                      status: EventStormHotspotStatus.open,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final beforeGaps = CostAutoSeeder.findUncoveredArtifacts(project);
      expect(beforeGaps.isComplete, isFalse);
      expect(beforeGaps.missingRunBaseline, isTrue);
      expect(beforeGaps.functionalRequirements, hasLength(1));
      expect(beforeGaps.nonFunctionalRequirements, hasLength(1));
      expect(beforeGaps.businessObjects, hasLength(1));
      expect(beforeGaps.eventStormHotspots, hasLength(1));
      expect(beforeGaps.totalUncoveredArtifacts, 4);

      final seeded = CostAutoSeeder.seedFromProject(project);
      final afterGaps = CostAutoSeeder.findUncoveredArtifacts(
        project.copyWith(costSpec: seeded.spec),
      );
      expect(afterGaps.isComplete, isTrue);
      expect(afterGaps.totalUncoveredArtifacts, 0);
      expect(afterGaps.missingRunBaseline, isFalse);
    });

    test('Outils IA FinOps : seed_cost_from_project, run_cost_coherence_audit, simulate_cost_scenario, get_enterprise_rate_card et get_cost_overview', () async {
      var project = SpecForgeProject.fromIdea(
        idea: 'Portail SaaS de gestion de flotte avec assistant IA',
        name: 'FleetAI',
        id: 'proj_fleet_ai',
      );
      project = project.copyWith(
        cahierDesCharges: SpecCahierDesCharges(
          modules: const [SpecModule(id: 'mod_flotte', name: 'Flotte')],
          functionalRequirements: [
            FunctionalRequirement(
              id: 'ef_1',
              code: 'EF-001',
              title: 'Enregistrer un véhicule',
              moduleId: 'mod_flotte',
              priority: RequirementPriority.must,
            ),
            FunctionalRequirement(
              id: 'ef_2',
              code: 'EF-002',
              title: 'Export analytique avancé',
              moduleId: 'mod_flotte',
              priority: RequirementPriority.could,
            ),
          ],
        ),
        eventStorming: EventStormingSpec(
          documents: [
            EventStormDocument(
              id: 'flotte',
              meta: const EventStormMeta(
                domain: 'Flotte',
                boundedContext: 'Véhicules',
                date: '2026-11-27',
              ),
              catalog: EventStormCatalog(
                aggregates: const [
                  EventStormCatalogItem(id: 'AGG-FLOTTE', name: 'Véhicule'),
                ],
              ),
              flow: [
                EventStormStep(
                  step: 1,
                  command: EventStormCommand(name: 'Synchroniser la flotte'),
                  aggregate: 'AGG-FLOTTE',
                  domainEvent: EventStormDomainEvent(
                    id: 'EVT-01',
                    name: 'Flotte synchronisée',
                  ),
                  hotspots: const [
                    EventStormHotspot(
                      id: 'HS-01',
                      question: 'Synchronisation télématique temps réel',
                      severity: EventStormHotspotSeverity.blocker,
                      status: EventStormHotspotStatus.open,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final enterpriseCard = EnterpriseRateCard.defaults.copyWith(
        currency: CostCurrency.chf,
        defaultDeliveryMode: CostDeliveryMode.inHouse,
        profiles: [
          for (final p in EnterpriseRateCard.defaults.profiles)
            if (p.id == 'prof_back')
              p.copyWith(internalDailyRate: 700.0, externalDailyRate: 1100.0)
            else
              p,
        ],
      );

      var updateCount = 0;
      final registry = SpecForgeToolRegistry.build(
        readProject: () => project,
        readEnterpriseRateCard: () => enterpriseCard,
        onUpdateProject: (updated) async {
          updateCount++;
          project = updated;
        },
        toolNames: SpecForgeToolRegistry.costStageToolNames,
      );

      expect(
        registry.declarations.map((d) => d.name),
        containsAll(<String>[
          'get_cost_overview',
          'inspect_cost_item',
          'run_cost_coherence_audit',
          'seed_cost_from_project',
          'simulate_cost_scenario',
          'get_enterprise_rate_card',
          'focus_cost_item',
          'get_example_mapping',
        ]),
      );

      // 1. Prévisualisation dry-run : ne mute pas le projet
      final dryRunRes = await registry.execute(
        VibeToolCall(
          id: 'c1',
          name: 'seed_cost_from_project',
          arguments: const <String, Object?>{'dryRun': true},
        ),
      );
      expect(dryRunRes.isError, isFalse);
      expect(dryRunRes.data['dryRun'], isTrue);
      expect(dryRunRes.data['applied'], isFalse);
      expect(dryRunRes.data['addedWbsCount'], 2);
      expect(dryRunRes.data['addedRiskCount'], 1);
      expect(updateCount, 0);
      expect(project.costSpec.wbsItems, isEmpty);

      // 2. Exécution réelle de l'amorçage non destructif
      final seedRes = await registry.execute(
        VibeToolCall(
          id: 'c2',
          name: 'seed_cost_from_project',
          arguments: const <String, Object?>{'dryRun': false},
        ),
      );
      expect(seedRes.isError, isFalse);
      expect(seedRes.data['applied'], isTrue);
      expect(updateCount, 1);
      expect(project.costSpec.wbsItems, hasLength(2));
      expect(project.costSpec.riskItems, hasLength(1));
      expect(
        SpecForgeToolRegistry.summarizeResult(
          VibeToolCall(id: 'c2', name: 'seed_cost_from_project'),
          seedRes,
        ),
        contains('+2 WBS'),
      );

      // 3. Vérification get_cost_overview (traçabilité + byDiscipline + uncoveredArtifacts)
      final overviewRes = await registry.execute(
        VibeToolCall(id: 'c3', name: 'get_cost_overview'),
      );
      expect(overviewRes.isError, isFalse);
      final wbsList = overviewRes.data['wbsItems'] as List;
      expect(wbsList, hasLength(2));
      expect((wbsList.first as Map)['requirementIds'], isNotEmpty);
      final summary = overviewRes.data['summary'] as Map;
      final fullLot = summary['fullLot'] as Map;
      expect(fullLot['byDiscipline'], isA<Map>());
      expect((fullLot['byDiscipline'] as Map).containsKey('backend'), isTrue);
      final uncovered = overviewRes.data['uncoveredArtifacts'] as Map;
      expect(uncovered['isComplete'], isTrue);

      // 4. Audit de cohérence FinOps filtrable par étape
      project = project.copyWith(
        costSpec: project.costSpec.copyWith(
          runItems: const <CostRunItemSpec>[],
        ),
      );
      final auditRunRes = await registry.execute(
        VibeToolCall(
          id: 'c4',
          name: 'run_cost_coherence_audit',
          arguments: const <String, Object?>{'stage': 'runOpex'},
        ),
      );
      expect(auditRunRes.isError, isFalse);
      expect(auditRunRes.data['stageFilter'], 'runOpex');
      expect((auditRunRes.data['issueCount'] as int), greaterThanOrEqualTo(2));
      expect(
        SpecForgeToolRegistry.summarizeResult(
          VibeToolCall(id: 'c4', name: 'run_cost_coherence_audit'),
          auditRunRes,
        ),
        contains('FinOps'),
      );

      // 5. Simulation « what-if » en lecture seule (ne mute pas le projet)
      final beforeSimSpec = project.costSpec;
      final simRes = await registry.execute(
        VibeToolCall(
          id: 'c5',
          name: 'simulate_cost_scenario',
          arguments: const <String, Object?>{
            'deliveryMode': 'fixedPrice',
            'aiEnabled': false,
            'rateMultiplier': 1.2,
            'excludePriorities': <String>['could'],
          },
        ),
      );
      expect(simRes.isError, isFalse);
      expect(project.costSpec, equals(beforeSimSpec));
      final deltas = simRes.data['deltas'] as Map;
      final simFull = (simRes.data['simulated'] as Map)['fullLot'] as Map;
      expect(simFull['itemCount'], 1);
      expect((deltas['mvpCost'] as Map)['delta'], greaterThan(0));
      expect(
        SpecForgeToolRegistry.summarizeResult(
          VibeToolCall(id: 'c5', name: 'simulate_cost_scenario'),
          simRes,
        ),
        contains('Simulation TCO 3 ans'),
      );

      // 6. Lecture et comparaison de la grille tarifaire d'entreprise
      project = project.copyWith(
        costSpec: project.costSpec.copyWith(
          currency: CostCurrency.eur,
          deliveryMode: CostDeliveryMode.hybrid,
        ),
      );
      final rateCardRes = await registry.execute(
        VibeToolCall(id: 'c6', name: 'get_enterprise_rate_card'),
      );
      expect(rateCardRes.isError, isFalse);
      expect(rateCardRes.data['source'], 'workspace');
      final cmp = rateCardRes.data['projectComparison'] as Map;
      expect(cmp['hasDivergence'], isTrue);
      expect((cmp['currencyDiff'] as Map)['enterprise'], 'CHF');
      expect((cmp['deliveryModeDiff'] as Map)['enterprise'], 'inHouse');
      expect(
        SpecForgeToolRegistry.summarizeResult(
          VibeToolCall(id: 'c6', name: 'get_enterprise_rate_card'),
          rateCardRes,
        ),
        contains('écarts détectés'),
      );

      // 7. Résumés pour get_event_storming & get_example_mapping
      final esRes = await registry.execute(
        VibeToolCall(id: 'c7', name: 'get_event_storming'),
      );
      expect(
        SpecForgeToolRegistry.summarizeResult(
          VibeToolCall(id: 'c7', name: 'get_event_storming'),
          esRes,
        ),
        contains('1 contexte(s)'),
      );
      final emRes = await registry.execute(
        VibeToolCall(id: 'c8', name: 'get_example_mapping'),
      );
      expect(
        SpecForgeToolRegistry.summarizeResult(
          VibeToolCall(id: 'c8', name: 'get_example_mapping'),
          emRes,
        ),
        contains('story(ies)'),
      );
    });
  });
}
