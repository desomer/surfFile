import 'package:flutter_test/flutter_test.dart';
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
          flows: [
            EventStormBoard(
              id: 'flow_1',
              code: 'ES-001',
              title: 'Flux Expédition',
              nodes: [
                EventStormNode(
                  id: 'hot_1',
                  kind: EventStormNodeKind.hotspot,
                  title: 'Quota API transporteur',
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
  });
}
