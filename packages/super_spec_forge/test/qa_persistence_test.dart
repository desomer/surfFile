import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecProjectStore — Persistance modulaire v3 du volet QA BDD/TDD', () {
    test('persiste qa/meta.json, qa/coherence_issues.json, qa/fixtures/, qa/features/, qa/tdd_suites/, chats/qa_<stage>.json et attachments/, puis recharge à l’identique', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_qa_pers_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final store = SpecProjectStore(tempDir);

      final fixture2 = QaFixtureSpec(
        id: 'fix_2',
        code: 'FIX-002',
        name: 'Encours dépassé',
        kind: QaFixtureKind.invalid,
        businessObjectId: 'obj_commande',
        personaId: 'persona_adv',
        businessRuleIds: const ['RG-001'],
        description: 'Commande dépassant le plafond autorisé.',
        payload: const <String, Object?>{
          'numero': 'CMD-2026-002',
          'montantHt': 48000,
          'statut': 'brouillon',
        },
        expectedValid: false,
        expectedErrorHint: 'Plafond d’encours dépassé (RG-001).',
      );

      final fixture1 = QaFixtureSpec(
        id: 'fix_1',
        code: 'FIX-001',
        name: 'Commande nominale',
        kind: QaFixtureKind.nominal,
        businessObjectId: 'obj_commande',
        personaId: 'persona_adv',
        businessRuleIds: const ['RG-001'],
        description: 'Commande valide sous plafond.',
        payload: const <String, Object?>{
          'numero': 'CMD-2026-001',
          'montantHt': 3500.5,
          'statut': 'brouillon',
          'lignes': <Map<String, Object?>>[
            {'codeArticle': 'SKU-10', 'quantite': 2},
          ],
        },
        expectedValid: true,
      );

      final feature2 = GherkinFeatureSpec(
        id: 'feat_2',
        code: 'FEAT-002',
        title: 'Gestion des litiges',
        moduleId: 'mod_ventes',
        tags: const ['@litiges'],
        scenarios: [
          GherkinScenarioSpec(
            id: 'scn_litige_1',
            code: 'SCN-002',
            title: 'Ouverture d’un dossier litige',
            steps: [
              GherkinStep(
                id: 'st_l1',
                keyword: GherkinStepKeyword.given,
                text: 'an approved order exists',
              ),
              GherkinStep(
                id: 'st_l2',
                keyword: GherkinStepKeyword.when,
                text: 'customer reports damaged parcel',
              ),
              GherkinStep(
                id: 'st_l3',
                keyword: GherkinStepKeyword.then,
                text: 'dispute ticket is created',
              ),
            ],
          ),
        ],
      );

      final feature1 = GherkinFeatureSpec(
        id: 'feat_1',
        code: 'FEAT-001',
        title: 'Validation commande',
        moduleId: 'mod_ventes',
        personaId: 'persona_adv',
        narrative:
            'As an ADV operator\nI want to validate compliant orders\nSo that credit risk stays controlled',
        tags: const ['@smoke', '@rg-001'],
        backgroundSteps: [
          GherkinStep(
            id: 'bg_1',
            keyword: GherkinStepKeyword.given,
            text: 'credit limits are loaded',
          ),
        ],
        scenarios: [
          GherkinScenarioSpec(
            id: 'scn_cmd_outline',
            code: 'SCN-001',
            title: 'Credit check for <montant>',
            isOutline: true,
            tags: const ['@outline'],
            steps: [
              GherkinStep(
                id: 'st_c1',
                keyword: GherkinStepKeyword.given,
                text: 'an order with amount <montant>',
              ),
              GherkinStep(
                id: 'st_c2',
                keyword: GherkinStepKeyword.when,
                text: 'ADV triggers validation',
              ),
              GherkinStep(
                id: 'st_c3',
                keyword: GherkinStepKeyword.then,
                text: 'order status becomes <resultat>',
              ),
            ],
            examples: GherkinExamplesTable(
              headers: const ['montant', 'resultat'],
              rows: const [
                ['3500.5', 'validee'],
                ['48000', 'rejetee'],
              ],
            ),
            requirementIds: const ['EXF-001'],
            businessRuleIds: const ['RG-001'],
            fixtureIds: const ['FIX-001', 'FIX-002'],
          ),
        ],
      );

      final suite2 = TddTestSuiteSpec(
        id: 'tdd_2',
        code: 'TDD-002',
        name: 'Calcul remise volume',
        layer: TddTargetLayer.calculationFormula,
        targetObjectId: 'obj_commande',
        cases: [
          TddTestCaseSpec(
            id: 'tc_remise_1',
            code: 'TC-003',
            order: 1,
            title: 'Applies 5% discount above 10 units',
            arrange: 'Order line with quantity = 12',
            act: 'pricing.computeDiscount(line)',
            outcomeKind: TddExpectedOutcomeKind.returnsValue,
            assertExpected: 'discountRate == 0.05',
          ),
        ],
      );

      final suite1 = TddTestSuiteSpec(
        id: 'tdd_1',
        code: 'TDD-001',
        name: 'Contrôle encours client',
        layer: TddTargetLayer.domainValidation,
        targetObjectId: 'obj_commande',
        moduleId: 'mod_ventes',
        description: 'Suite Red -> Green -> Refactor sur RG-001.',
        cases: [
          TddTestCaseSpec(
            id: 'tc_encours_1',
            code: 'TC-001',
            order: 1,
            title: 'Approves compliant order FIX-001',
            fixtureId: 'FIX-001',
            arrange: 'Load FIX-001 with client limit 10000',
            act: 'validator.validate(order, client)',
            outcomeKind: TddExpectedOutcomeKind.mutatesState,
            assertExpected: 'order.statut == "validee"',
            businessRuleIds: const ['RG-001'],
          ),
          TddTestCaseSpec(
            id: 'tc_encours_2',
            code: 'TC-002',
            order: 2,
            title: 'Rejects order FIX-002 above credit limit',
            fixtureId: 'FIX-002',
            arrange: 'Load FIX-002 with client limit 10000',
            act: 'validator.validate(order, client)',
            outcomeKind: TddExpectedOutcomeKind.rejectsWithError,
            assertExpected: 'order.statut == "brouillon"',
            expectedErrorMessage: 'Plafond d’encours dépassé (RG-001).',
            businessRuleIds: const ['RG-001'],
          ),
        ],
      );

      final qaChatMessageWithAttachments = SpecChatMessage(
        id: 'qa_msg_1',
        isUser: true,
        text: 'Voici la matrice de cas limites et la capture du rapport.',
        attachments: [
          VibeChatAttachment.text(
            name: 'qa_matrix.md',
            content: '# Matrice QA\n- FIX-001 nominal\n- FIX-002 hors plafond',
          ),
          VibeChatAttachment.image(
            name: 'coverage_badge.png',
            bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]),
          ),
        ],
        timestamp: DateTime.utc(2026, 11, 22, 14, 10),
      );

      final qaAssistantReply = SpecChatMessage(
        id: 'qa_msg_2',
        isUser: false,
        text: 'Suites TDD-001 et TDD-002 générées avec 3 cas atomiques.',
        appliedPatchSummary: '2 suite(s) TDD (3 cas)',
        stageReadyToAdvance: true,
        timestamp: DateTime.utc(2026, 11, 22, 14, 11),
      );

      final saved =
          SpecForgeProject.fromIdea(
            idea: 'Portail commandes et encours B2B',
            name: 'Portail Commandes QA',
            id: 'proj_qa_b2b',
          ).copyWith(
            businessObjects: [
              BusinessObjectSpec(
                id: 'obj_commande',
                name: 'Commande',
                technicalName: 'Commande',
                attributes: [
                  BusinessAttribute(
                    id: 'attr_num',
                    name: 'numero',
                    required: true,
                  ),
                ],
              ),
            ],
            businessRules: [
              BusinessRuleSpec(
                id: 'r_1',
                code: 'RG-001',
                title: 'Plafond encours client',
                targetObjectIds: const ['obj_commande'],
              ),
            ],
            qaSpec: QaForgeSpec(
              currentStage: QaForgeStage.tddSuites,
              gherkinLanguage: GherkinKeywordLanguage.en,
              // Ordre volontairement non alphabétique pour vérifier _order.json
              fixtures: [fixture2, fixture1],
              features: [feature2, feature1],
              tddSuites: [suite2, suite1],
              stageStates: {
                QaForgeStage.testFixtures: QaStageState(
                  stage: QaForgeStage.testFixtures,
                  status: SpecStageStatus.validated,
                  stageSummary: '2 fixtures validées.',
                  readyToAdvance: true,
                ),
                QaForgeStage.gherkinFeatures: QaStageState(
                  stage: QaForgeStage.gherkinFeatures,
                  status: SpecStageStatus.validated,
                  stageSummary: '2 features Gherkin validées.',
                  readyToAdvance: true,
                ),
                QaForgeStage.tddSuites: QaStageState(
                  stage: QaForgeStage.tddSuites,
                  status: SpecStageStatus.inProgress,
                  messages: [qaChatMessageWithAttachments, qaAssistantReply],
                  stageSummary: '2 suites TDD (3 cas).',
                  readyToAdvance: true,
                ),
              },
              coherenceIssues: const [
                QaCoherenceIssue(
                  id: 'qa_coh_1',
                  severity: CoherenceSeverity.info,
                  stage: QaForgeStage.qaReviewExport,
                  code: 'QA-MUTATION-HINT',
                  title: 'Ajouter un cas à la borne exacte 10 000 EUR',
                  description: 'Vérifier l’égalité stricte sur le plafond.',
                  targetRef: 'TDD-001',
                  suggestion: 'Ajouter TC-004 pour montant == plafond.',
                  source: 'ai',
                ),
              ],
            ),
          );

      await store.saveProject(saved);

      final projDir =
          '${tempDir.path}${sep}projects${sep}portail-commandes-qa';

      // Vérification de l'arborescence QA et chats sur disque
      final metaFile = File('$projDir${sep}qa${sep}meta.json');
      final issuesFile = File('$projDir${sep}qa${sep}coherence_issues.json');
      final fixturesOrderFile = File(
        '$projDir${sep}qa${sep}fixtures${sep}_order.json',
      );
      final fix1File = File(
        '$projDir${sep}qa${sep}fixtures${sep}fix-001-commande-nominale.json',
      );
      final fix2File = File(
        '$projDir${sep}qa${sep}fixtures${sep}fix-002-encours-depasse.json',
      );
      final featuresOrderFile = File(
        '$projDir${sep}qa${sep}features${sep}_order.json',
      );
      final feat1File = File(
        '$projDir${sep}qa${sep}features${sep}feat-001-validation-commande.json',
      );
      final feat2File = File(
        '$projDir${sep}qa${sep}features${sep}feat-002-gestion-des-litiges.json',
      );
      final suitesOrderFile = File(
        '$projDir${sep}qa${sep}tdd_suites${sep}_order.json',
      );
      final suite1File = File(
        '$projDir${sep}qa${sep}tdd_suites${sep}tdd-001-controle-encours-client.json',
      );
      final suite2File = File(
        '$projDir${sep}qa${sep}tdd_suites${sep}tdd-002-calcul-remise-volume.json',
      );

      expect(await metaFile.exists(), isTrue);
      expect(await issuesFile.exists(), isTrue);
      expect(await fixturesOrderFile.exists(), isTrue);
      expect(await fix1File.exists(), isTrue);
      expect(await fix2File.exists(), isTrue);
      expect(await featuresOrderFile.exists(), isTrue);
      expect(await feat1File.exists(), isTrue);
      expect(await feat2File.exists(), isTrue);
      expect(await suitesOrderFile.exists(), isTrue);
      expect(await suite1File.exists(), isTrue);
      expect(await suite2File.exists(), isTrue);

      final metaRaw =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      expect(metaRaw['format'], SpecProjectStore.qaMetaFormat);
      expect(metaRaw['currentStage'], 'tddSuites');
      expect(metaRaw['gherkinLanguage'], 'en');

      for (final stage in QaForgeStage.values) {
        final qaChatFile = File(
          '$projDir${sep}chats${sep}qa_${stage.name}.json',
        );
        expect(
          await qaChatFile.exists(),
          isTrue,
          reason: 'Le fichier chats/qa_${stage.name}.json doit exister.',
        );
      }

      // Vérifie que les pièces jointes du chat QA sont externalisées dans attachments/
      final tddChatRaw = jsonDecode(
        await File('$projDir${sep}chats${sep}qa_tddSuites.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(tddChatRaw['format'], SpecProjectStore.qaStageChatFormat);
      final rawMsgList =
          (tddChatRaw['data'] as Map<String, dynamic>)['messages']
              as List<dynamic>;
      final rawAtts =
          (rawMsgList.first as Map<String, dynamic>)['attachments']
              as List<dynamic>;
      expect(rawAtts.length, 2);
      for (final rawAtt in rawAtts.cast<Map<String, dynamic>>()) {
        final storageFile = rawAtt['storageFile'] as String?;
        expect(storageFile, isNotNull);
        expect(
          await File('$projDir${sep}attachments$sep$storageFile').exists(),
          isTrue,
        );
        expect(rawAtt.containsKey('bytesBase64'), isFalse);
      }

      // Rechargement depuis l'instance courante et depuis une instance fraîche de SpecProjectStore
      final reloaded = await store.loadProject('proj_qa_b2b');
      expect(reloaded, isNotNull);
      expect(reloaded, equals(saved));

      final freshStore = SpecProjectStore(tempDir);
      final reloadedFresh = await freshStore.loadProject('proj_qa_b2b');
      expect(reloadedFresh, equals(saved));
      expect(
        reloadedFresh!.qaSpec.gherkinLanguage,
        GherkinKeywordLanguage.en,
      );
      expect(reloadedFresh.qaSpec.fixtures.map((f) => f.id).toList(), [
        'fix_2',
        'fix_1',
      ]);
      expect(reloadedFresh.qaSpec.features.map((f) => f.id).toList(), [
        'feat_2',
        'feat_1',
      ]);
      expect(reloadedFresh.qaSpec.tddSuites.map((s) => s.id).toList(), [
        'tdd_2',
        'tdd_1',
      ]);
      final hydratedAtts = reloadedFresh.qaSpec
          .stageStateFor(QaForgeStage.tddSuites)
          .messages
          .first
          .attachments;
      expect(
        hydratedAtts[0].textContent,
        '# Matrice QA\n- FIX-001 nominal\n- FIX-002 hors plafond',
      );
      expect(hydratedAtts[1].isImage, isTrue);

      // Vérification de listProjects() : featureCount, tddCaseCount et currentQaStage
      final summaries = await freshStore.listProjects();
      expect(summaries.length, 1);
      expect(summaries.single.id, 'proj_qa_b2b');
      expect(summaries.single.featureCount, 2);
      expect(summaries.single.tddCaseCount, 3);
      expect(summaries.single.currentQaStage, QaForgeStage.tddSuites);
    });

    test('renommage et suppression de fixtures, features et suites TDD élaguent proprement les anciens fichiers <slug>.json', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_qa_prune_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final store = SpecProjectStore(tempDir);

      final fix1 = QaFixtureSpec(
        id: 'fix_1',
        code: 'FIX-001',
        name: 'Fixture Initiale',
      );
      final fix2 = QaFixtureSpec(
        id: 'fix_2',
        code: 'FIX-002',
        name: 'Fixture A Supprimer',
      );
      final feat1 = GherkinFeatureSpec(
        id: 'feat_1',
        code: 'FEAT-001',
        title: 'Feature Initiale',
      );
      final feat2 = GherkinFeatureSpec(
        id: 'feat_2',
        code: 'FEAT-002',
        title: 'Feature A Supprimer',
      );
      final suite1 = TddTestSuiteSpec(
        id: 'tdd_1',
        code: 'TDD-001',
        name: 'Suite Initiale',
        cases: [
          TddTestCaseSpec(id: 'tc_1', code: 'TC-001', title: 'Cas 1'),
        ],
      );
      final suite2 = TddTestSuiteSpec(
        id: 'tdd_2',
        code: 'TDD-002',
        name: 'Suite A Supprimer',
        cases: [
          TddTestCaseSpec(id: 'tc_2', code: 'TC-002', title: 'Cas 2'),
        ],
      );

      final initial =
          SpecForgeProject.fromIdea(
            idea: 'Contrôle qualité logistique',
            name: 'QualiOps',
            id: 'proj_qualiops',
          ).copyWith(
            qaSpec: QaForgeSpec(
              currentStage: QaForgeStage.qaReviewExport,
              fixtures: [fix1, fix2],
              features: [feat1, feat2],
              tddSuites: [suite1, suite2],
            ),
          );

      await store.saveProject(initial);

      final projDir = '${tempDir.path}${sep}projects${sep}quali-ops';
      final fix1OldFile = File(
        '$projDir${sep}qa${sep}fixtures${sep}fix-001-fixture-initiale.json',
      );
      final fix2OldFile = File(
        '$projDir${sep}qa${sep}fixtures${sep}fix-002-fixture-a-supprimer.json',
      );
      final feat1OldFile = File(
        '$projDir${sep}qa${sep}features${sep}feat-001-feature-initiale.json',
      );
      final feat2OldFile = File(
        '$projDir${sep}qa${sep}features${sep}feat-002-feature-a-supprimer.json',
      );
      final suite1OldFile = File(
        '$projDir${sep}qa${sep}tdd_suites${sep}tdd-001-suite-initiale.json',
      );
      final suite2OldFile = File(
        '$projDir${sep}qa${sep}tdd_suites${sep}tdd-002-suite-a-supprimer.json',
      );

      expect(await fix1OldFile.exists(), isTrue);
      expect(await fix2OldFile.exists(), isTrue);
      expect(await feat1OldFile.exists(), isTrue);
      expect(await feat2OldFile.exists(), isTrue);
      expect(await suite1OldFile.exists(), isTrue);
      expect(await suite2OldFile.exists(), isTrue);

      // Sauvegarde incrémentale : renommage de fix1/feat1/suite1 + suppression de fix2/feat2/suite2
      final updated = initial.copyWith(
        qaSpec: initial.qaSpec.copyWith(
          fixtures: [
            fix1.copyWith(code: 'FIX-010', name: 'Fixture Renommée Quai'),
          ],
          features: [
            feat1.copyWith(code: 'FEAT-010', title: 'Feature Réception Quai'),
          ],
          tddSuites: [
            suite1.copyWith(
              code: 'TDD-010',
              name: 'Suite Contrôle Quai',
              cases: [
                ...suite1.cases,
                TddTestCaseSpec(
                  id: 'tc_3',
                  code: 'TC-003',
                  order: 2,
                  title: 'Cas additionnel',
                ),
              ],
            ),
          ],
        ),
      );
      await store.saveProject(updated);

      final fix1NewFile = File(
        '$projDir${sep}qa${sep}fixtures${sep}fix-010-fixture-renommee-quai.json',
      );
      final feat1NewFile = File(
        '$projDir${sep}qa${sep}features${sep}feat-010-feature-reception-quai.json',
      );
      final suite1NewFile = File(
        '$projDir${sep}qa${sep}tdd_suites${sep}tdd-010-suite-controle-quai.json',
      );

      expect(await fix1OldFile.exists(), isFalse);
      expect(await fix2OldFile.exists(), isFalse);
      expect(await feat1OldFile.exists(), isFalse);
      expect(await feat2OldFile.exists(), isFalse);
      expect(await suite1OldFile.exists(), isFalse);
      expect(await suite2OldFile.exists(), isFalse);
      expect(await fix1NewFile.exists(), isTrue);
      expect(await feat1NewFile.exists(), isTrue);
      expect(await suite1NewFile.exists(), isTrue);

      final summaries = await store.listProjects();
      expect(summaries.single.featureCount, 1);
      expect(summaries.single.tddCaseCount, 2);
      expect(summaries.single.currentQaStage, QaForgeStage.qaReviewExport);

      final reloaded = await SpecProjectStore(tempDir)
          .loadProject('proj_qualiops');
      expect(reloaded, equals(updated));
    });

    test('projet v3 existant sans dossier qa/ se charge avec QaForgeSpec.empty et ne crée pas qa/ tant qu’aucun contenu QA n’est ajouté', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_v3_noqa_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final projDir = Directory(
        '${tempDir.path}${sep}projects${sep}legacy-no-qa-app',
      );
      await Directory('${projDir.path}${sep}spec').create(recursive: true);
      await Directory('${projDir.path}${sep}chats').create(recursive: true);

      // Construction d'un dossier projet v3 préexistant dépourvu de dossier qa/ et de clés QA dans project.json
      await File('${projDir.path}${sep}project.json').writeAsString(
        SpecStorageIo.encodePrettyJson({
          'format': SpecProjectStore.manifestFormat,
          'version': SpecProjectStore.storageVersion,
          'id': 'proj_legacy_no_qa',
          'name': 'Legacy No QA App',
          'initialIdea': 'Facturation récurrente B2B',
          'createdAt': '2026-06-01T08:00:00.000Z',
          'updatedAt': '2026-06-01T09:00:00.000Z',
          'currentStage': 'businessRules',
        }),
      );
      await File('${projDir.path}${sep}spec${sep}lexicon.json').writeAsString(
        SpecStorageIo.encodePrettyJson({
          'format': 'super_spec_forge.lexicon',
          'version': SpecProjectStore.storageVersion,
          'data': {
            'terms': [
              {
                'id': 't_facture',
                'term': 'Facture',
                'definition': 'Pièce comptable émise au client',
              },
            ],
          },
        }),
      );

      final store = SpecProjectStore(tempDir);
      final qaDir = Directory('${projDir.path}${sep}qa');
      final qaFixturesChatFile = File(
        '${projDir.path}${sep}chats${sep}qa_testFixtures.json',
      );

      expect(await qaDir.exists(), isFalse);
      expect(await qaFixturesChatFile.exists(), isFalse);

      // 1. Chargement propre avec QaForgeSpec.empty sans créer qa/
      final loaded = await store.loadProject('proj_legacy_no_qa');
      expect(loaded, isNotNull);
      expect(loaded!.qaSpec, equals(QaForgeSpec.empty));
      expect(loaded.qaSpec.hasContent, isFalse);
      expect(await qaDir.exists(), isFalse);
      expect(await qaFixturesChatFile.exists(), isFalse);

      final initialSummaries = await store.listProjects();
      expect(initialSummaries.single.featureCount, 0);
      expect(initialSummaries.single.tddCaseCount, 0);
      expect(initialSummaries.single.currentQaStage, QaForgeStage.testFixtures);

      // 2. Sauvegarde incrémentale purement métier : toujours aucun fichier sous qa/ ni chats/qa_*.json
      final specOnlyUpdate = loaded.copyWith(
        vision: loaded.vision.copyWith(
          problemStatement: 'Retards de facturation mensuelle',
        ),
      );
      await store.saveProject(specOnlyUpdate);
      expect(await qaDir.exists(), isFalse);
      expect(await qaFixturesChatFile.exists(), isFalse);

      // 3. Dès qu'un contenu QA est ajouté, qa/ et chats/qa_*.json sont initialisés proprement
      final withQa = specOnlyUpdate.copyWith(
        qaSpec: QaForgeSpec(
          currentStage: QaForgeStage.gherkinFeatures,
          gherkinLanguage: GherkinKeywordLanguage.en,
          fixtures: [
            QaFixtureSpec(
              id: 'fix_facture',
              code: 'FIX-001',
              name: 'Facture mensuelle valide',
            ),
          ],
          features: [
            GherkinFeatureSpec(
              id: 'feat_facturation',
              code: 'FEAT-001',
              title: 'Émission facture',
            ),
          ],
          tddSuites: [
            TddTestSuiteSpec(
              id: 'tdd_facture',
              code: 'TDD-001',
              name: 'Calcul échéance',
              cases: [
                TddTestCaseSpec(
                  id: 'tc_echeance',
                  code: 'TC-001',
                  title: 'Calcule date + 30 jours fin de mois',
                ),
              ],
            ),
          ],
        ),
      );
      await store.saveProject(withQa);

      expect(await qaDir.exists(), isTrue);
      expect(await File('${qaDir.path}${sep}meta.json').exists(), isTrue);
      expect(
        await File('${qaDir.path}${sep}coherence_issues.json').exists(),
        isTrue,
      );
      expect(
        await File(
          '${qaDir.path}${sep}fixtures${sep}fix-001-facture-mensuelle-valide.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${qaDir.path}${sep}features${sep}feat-001-emission-facture.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${qaDir.path}${sep}tdd_suites${sep}tdd-001-calcul-echeance.json',
        ).exists(),
        isTrue,
      );
      expect(await qaFixturesChatFile.exists(), isTrue);

      final reloadedWithQa = await SpecProjectStore(tempDir)
          .loadProject('proj_legacy_no_qa');
      expect(reloadedWithQa, equals(withQa));
    });
  });
}
