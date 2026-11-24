import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('Persistance modulaire Git-friendly du volet Coûts IT & Grille TJM Entreprise', () {
    test('EnterpriseRateCardStore sauvegarde, recharge et encode/décode proprement la grille TJM', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_rate_card_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = EnterpriseRateCardStore(tempDir);
      expect(await store.load(), equals(EnterpriseRateCard.defaults));

      final customCard = EnterpriseRateCard.defaults.copyWith(
        currency: CostCurrency.chf,
        hoursPerDay: 8.0,
        defaultDeliveryMode: CostDeliveryMode.timeAndMaterials,
        notes: 'Grille Suisse 2026',
      );
      await store.save(customCard);

      final reloaded = await store.load();
      expect(reloaded, equals(customCard));

      final exported = EnterpriseRateCardStore.encodePrettyJson(customCard);
      expect(EnterpriseRateCardStore.decodeJsonString(exported), equals(customCard));
    });

    test('SpecProjectStore persiste cost/assumptions.json, wbs/, run/, risks/, coherence_issues.json et chats/cost_*.json', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_cost_pers_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = SpecProjectStore(tempDir);
      final baseProject = SpecForgeProject.fromIdea(
        idea: 'ERP industriel modulaire',
        name: 'IndusFlow',
        id: 'proj_indus',
      );
      await store.saveProject(baseProject);

      final sep = Platform.pathSeparator;
      final projectsRoot = Directory('${tempDir.path}${sep}projects');
      final projectDir = projectsRoot.listSync().whereType<Directory>().single;
      final costDir = Directory('${projectDir.path}${sep}cost');
      expect(await costDir.exists(), isFalse);

      final richCost = CostForgeSpec(
        currentStage: CostForgeStage.buildWbs,
        currency: CostCurrency.eur,
        hoursPerDay: 8.0,
        deliveryMode: CostDeliveryMode.fixedPrice,
        targetUsersCount: 500,
        assumptionsNotes: 'Forfait incluant garantie 3 mois',
        wbsItems: [
          CostWbsItemSpec(
            id: 'wbs_a',
            code: 'WBS-001',
            title: 'Gestion des ordres de fabrication',
            discipline: CostDiscipline.backend,
            priority: RequirementPriority.must,
            profileId: 'prof_back',
            optimisticDays: 5,
            mostLikelyDays: 8,
            pessimisticDays: 14,
          ),
        ],
        runItems: const [
          CostRunItemSpec(
            id: 'run_a',
            code: 'RUN-001',
            name: 'Hébergement Cloud Prod',
            category: CostRunCategory.cloudInfra,
            environment: CostEnvironmentScope.prod,
            billingCycle: CostBillingCycle.monthly,
            unitCost: 420.0,
          ),
        ],
        riskItems: [
          CostRiskItemSpec(
            id: 'rsk_a',
            code: 'RSK-001',
            title: 'Interopérabilité automate atelier',
            probabilityPct: 40,
            impactDays: 6,
            mitigation: 'POC protocole OPC-UA dès le sprint 0',
          ),
        ],
        coherenceIssues: const [
          CostCoherenceIssue(
            id: 'iss_cost_1',
            severity: CoherenceSeverity.warning,
            stage: CostForgeStage.runOpex,
            code: 'COST-AI-HINT',
            title: 'Prévoir environnement de pré-production',
            description: 'Aucun poste staging dédié.',
            source: 'ai',
          ),
        ],
        stageStates: <CostForgeStage, CostStageState>{
          CostForgeStage.rateCardAssumptions: CostStageState(
            stage: CostForgeStage.rateCardAssumptions,
            status: SpecStageStatus.validated,
            stageSummary: 'TJM validés.',
            messages: [
              SpecChatMessage(
                id: 'cmsg_1',
                isUser: true,
                text: 'Calibre le forfait.',
              ),
            ],
          ),
        },
      );

      final updatedProject = baseProject.copyWith(costSpec: richCost);
      await store.saveProject(updatedProject);

      expect(await File('${costDir.path}${sep}assumptions.json').exists(), isTrue);
      expect(await Directory('${costDir.path}${sep}wbs').exists(), isTrue);
      expect(await Directory('${costDir.path}${sep}run').exists(), isTrue);
      expect(await Directory('${costDir.path}${sep}risks').exists(), isTrue);
      expect(await File('${costDir.path}${sep}coherence_issues.json').exists(), isTrue);

      final summaries = await store.listProjects();
      expect(summaries.single.wbsItemCount, 1);
      expect(summaries.single.runItemCount, 1);
      expect(summaries.single.currentCostStage, CostForgeStage.buildWbs);

      final reloaded = await store.loadProject(updatedProject.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.costSpec, equals(richCost));
    });
  });
}
