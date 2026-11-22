import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecProjectStore — Persistance modulaire v3 du volet UX', () {
    test('persiste ux/navigation.json, ux/coherence_issues.json, ux/journeys/, ux/screens/, chats/ux_<stage>.json et attachments/, puis recharge à l’identique', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_ux_pers_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final store = SpecProjectStore(tempDir);

      final journey2 = UxJourneySpec(
        id: 'jrn_2',
        code: 'JRN-002',
        name: 'Traitement litige transport',
        personaId: 'persona_adv',
        channel: UxTargetChannel.webResponsive,
        trigger: 'Réserve émise à la livraison',
        goal: 'Émettre un avoir ou une réexpédition',
        steps: const [
          UxJourneyStep(
            id: 'st_litige_1',
            order: 1,
            title: 'Qualification du litige',
            actorAction: 'Joint le constat transporteur',
            systemResponse: 'Crée le dossier litige relié à la commande',
            targetRouteId: 'route_litiges',
          ),
        ],
        successCriteria: const ['Dossier instruit en moins de 3 minutes'],
      );

      final journey1 = UxJourneySpec(
        id: 'jrn_1',
        code: 'JRN-001',
        name: 'Prise de commande express',
        personaId: 'persona_adv',
        useCaseIds: const ['uc_1'],
        requirementIds: const ['EXF-001'],
        channel: UxTargetChannel.desktop,
        steps: const [
          UxJourneyStep(
            id: 'st_cmd_1',
            order: 1,
            title: 'Saisie des lignes',
            targetRouteId: 'route_commandes',
          ),
        ],
      );

      final navigation = UxNavigationSpec(
        shellPattern: UxShellPattern.navigationRail,
        hasAppBar: true,
        hasBreadcrumbs: true,
        hasGlobalSearch: true,
        homeRouteId: 'route_commandes',
        visualTheme: const UxVisualThemeSeed(
          accentHex: '#0D9488',
          themeMode: 'dark',
          surfaceSystem: 'material',
          fontFamily: 'Plus Jakarta Sans',
          density: UxDensityProfile.compact,
          cardRadius: 12.0,
          uxVoiceGuidelines: 'Micro-copie concise orientée productivité.',
        ),
        routes: [
          UxRouteNode(
            id: 'route_commandes',
            path: '/commandes',
            title: 'Commandes',
            iconName: 'shopping_bag_outlined',
            moduleId: 'mod_ventes',
          ),
          UxRouteNode(
            id: 'route_litiges',
            path: '/litiges',
            title: 'Litiges transport',
            iconName: 'report_problem_outlined',
            permissionRuleIds: const ['RG-002'],
          ),
        ],
      );

      final screen2 = UxScreenSpec(
        id: 'scr_2',
        code: 'SCR-002',
        name: 'Suivi des litiges',
        routeId: 'route_litiges',
        pattern: UxScreenPattern.tableExplorer,
        zones: UxScreenSpec.defaultZonesForPattern(
          UxScreenPattern.tableExplorer,
        ),
      );

      final screen1 = UxScreenSpec(
        id: 'scr_1',
        code: 'SCR-001',
        name: 'Poste Commandes & Panier',
        routeId: 'route_commandes',
        pattern: UxScreenPattern.masterDetail,
        primaryObjectId: 'obj_commande',
        zones: UxScreenSpec.defaultZonesForPattern(
          UxScreenPattern.masterDetail,
        ),
        actions: [
          UxScreenAction(
            id: 'act_valider',
            label: 'Valider',
            hierarchy: UxActionHierarchy.primary,
            businessRuleIds: const ['RG-001'],
          ),
        ],
        states: UxScreenStatesSpec(
          emptyStateTitle: 'Aucune commande active',
          emptyStateCta: 'Nouvelle commande',
          loadingPattern: 'skeleton',
          errorHandling: 'Toast + focus premier champ en erreur',
          readOnlyRuleIds: const ['RG-001'],
        ),
      );

      final uxChatMessageWithAttachments = SpecChatMessage(
        id: 'ux_msg_1',
        isUser: true,
        text: 'Voici la note de cadrage UX et la capture filaire.',
        attachments: [
          VibeChatAttachment.text(
            name: 'ux_notes.md',
            content: '# Maquette\n- Rail gauche\n- Détail commande',
          ),
          VibeChatAttachment.image(
            name: 'wireframe.png',
            bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 9, 8, 7, 6]),
          ),
        ],
        timestamp: DateTime.utc(2026, 11, 22, 10, 30),
      );

      final uxAssistantReply = SpecChatMessage(
        id: 'ux_msg_2',
        isUser: false,
        text: 'Schéma directeur SCR-001 structuré.',
        appliedPatchSummary: '2 écran(s) UX',
        stageReadyToAdvance: true,
        timestamp: DateTime.utc(2026, 11, 22, 10, 31),
      );

      final saved =
          SpecForgeProject.fromIdea(
            idea: 'Portail commandes et litiges B2B',
            name: 'Portail Commandes B2B',
            id: 'proj_b2b',
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
                title: 'Numéro obligatoire',
                targetObjectIds: const ['obj_commande'],
              ),
            ],
            uxSpec: UxForgeSpec(
              currentStage: UxForgeStage.screenBlueprints,
              // Ordre volontairement non alphabétique pour vérifier _order.json
              journeys: [journey2, journey1],
              navigation: navigation,
              screens: [screen2, screen1],
              stageStates: {
                UxForgeStage.userJourneys: UxStageState(
                  stage: UxForgeStage.userJourneys,
                  status: SpecStageStatus.validated,
                  stageSummary: '2 parcours validés.',
                  readyToAdvance: true,
                ),
                UxForgeStage.iaNavigation: UxStageState(
                  stage: UxForgeStage.iaNavigation,
                  status: SpecStageStatus.validated,
                  stageSummary: 'NavigationRail + 2 routes.',
                  readyToAdvance: true,
                ),
                UxForgeStage.screenBlueprints: UxStageState(
                  stage: UxForgeStage.screenBlueprints,
                  status: SpecStageStatus.inProgress,
                  messages: [uxChatMessageWithAttachments, uxAssistantReply],
                  stageSummary: '2 écrans modélisés.',
                  readyToAdvance: true,
                ),
              },
              coherenceIssues: const [
                UxCoherenceIssue(
                  id: 'ux_coh_1',
                  severity: CoherenceSeverity.info,
                  stage: UxForgeStage.uxReviewExport,
                  code: 'UX-A11Y-CONTRAST',
                  title: 'Vérifier le contraste en mode sombre',
                  description: 'Contraste AA requis sur les badges statut.',
                  targetRef: 'SCR-001',
                  suggestion: 'Utiliser theme:onSecondaryContainer.',
                  source: 'ai',
                ),
              ],
            ),
          );

      await store.saveProject(saved);

      final projDir =
          '${tempDir.path}${sep}projects${sep}portail-commandes-b2b';

      // Vérification de l'arborescence UX et chats sur disque
      final navFile = File('$projDir${sep}ux${sep}navigation.json');
      final issuesFile = File('$projDir${sep}ux${sep}coherence_issues.json');
      final journeysOrderFile = File(
        '$projDir${sep}ux${sep}journeys${sep}_order.json',
      );
      final j1File = File(
        '$projDir${sep}ux${sep}journeys${sep}jrn-001-prise-de-commande-express.json',
      );
      final j2File = File(
        '$projDir${sep}ux${sep}journeys${sep}jrn-002-traitement-litige-transport.json',
      );
      final screensOrderFile = File(
        '$projDir${sep}ux${sep}screens${sep}_order.json',
      );
      final s1File = File(
        '$projDir${sep}ux${sep}screens${sep}scr-001-poste-commandes-panier.json',
      );
      final s2File = File(
        '$projDir${sep}ux${sep}screens${sep}scr-002-suivi-des-litiges.json',
      );

      expect(await navFile.exists(), isTrue);
      expect(await issuesFile.exists(), isTrue);
      expect(await journeysOrderFile.exists(), isTrue);
      expect(await j1File.exists(), isTrue);
      expect(await j2File.exists(), isTrue);
      expect(await screensOrderFile.exists(), isTrue);
      expect(await s1File.exists(), isTrue);
      expect(await s2File.exists(), isTrue);

      for (final stage in UxForgeStage.values) {
        final uxChatFile = File(
          '$projDir${sep}chats${sep}ux_${stage.name}.json',
        );
        expect(
          await uxChatFile.exists(),
          isTrue,
          reason: 'Le fichier chats/ux_${stage.name}.json doit exister.',
        );
      }

      // Vérifie que les pièces jointes du chat UX sont externalisées dans attachments/
      final blueprintsChatRaw = jsonDecode(
        await File('$projDir${sep}chats${sep}ux_screenBlueprints.json')
            .readAsString(),
      ) as Map<String, dynamic>;
      expect(blueprintsChatRaw['format'], SpecProjectStore.uxStageChatFormat);
      final rawMsgList =
          (blueprintsChatRaw['data'] as Map<String, dynamic>)['messages']
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
      final reloaded = await store.loadProject('proj_b2b');
      expect(reloaded, isNotNull);
      expect(reloaded, equals(saved));

      final freshStore = SpecProjectStore(tempDir);
      final reloadedFresh = await freshStore.loadProject('proj_b2b');
      expect(reloadedFresh, equals(saved));
      expect(reloadedFresh!.uxSpec.journeys.map((j) => j.id).toList(), [
        'jrn_2',
        'jrn_1',
      ]);
      expect(reloadedFresh.uxSpec.screens.map((s) => s.id).toList(), [
        'scr_2',
        'scr_1',
      ]);
      final hydratedAtts = reloadedFresh.uxSpec
          .stageStateFor(UxForgeStage.screenBlueprints)
          .messages
          .first
          .attachments;
      expect(
        hydratedAtts[0].textContent,
        '# Maquette\n- Rail gauche\n- Détail commande',
      );
      expect(hydratedAtts[1].isImage, isTrue);

      // Vérification de listProjects() : journeyCount, screenCount et currentUxStage
      final summaries = await freshStore.listProjects();
      expect(summaries.length, 1);
      expect(summaries.single.id, 'proj_b2b');
      expect(summaries.single.journeyCount, 2);
      expect(summaries.single.screenCount, 2);
      expect(summaries.single.currentUxStage, UxForgeStage.screenBlueprints);
    });

    test('renommage et suppression d’un parcours ou d’un écran élaguent proprement les anciens fichiers <slug>.json', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_ux_prune_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final store = SpecProjectStore(tempDir);

      final j1 = UxJourneySpec(
        id: 'jrn_1',
        code: 'JRN-001',
        name: 'Parcours Initial',
      );
      final j2 = UxJourneySpec(
        id: 'jrn_2',
        code: 'JRN-002',
        name: 'Parcours À Supprimer',
      );
      final s1 = UxScreenSpec(
        id: 'scr_1',
        code: 'SCR-001',
        name: 'Écran Initial',
      );
      final s2 = UxScreenSpec(
        id: 'scr_2',
        code: 'SCR-002',
        name: 'Écran À Supprimer',
      );

      final initial =
          SpecForgeProject.fromIdea(
            idea: 'Suivi d’interventions',
            name: 'FieldOps',
            id: 'proj_fieldops',
          ).copyWith(
            uxSpec: UxForgeSpec(
              currentStage: UxForgeStage.uxReviewExport,
              journeys: [j1, j2],
              screens: [s1, s2],
            ),
          );

      await store.saveProject(initial);

      final projDir = '${tempDir.path}${sep}projects${sep}field-ops';
      final j1OldFile = File(
        '$projDir${sep}ux${sep}journeys${sep}jrn-001-parcours-initial.json',
      );
      final j2OldFile = File(
        '$projDir${sep}ux${sep}journeys${sep}jrn-002-parcours-a-supprimer.json',
      );
      final s1OldFile = File(
        '$projDir${sep}ux${sep}screens${sep}scr-001-ecran-initial.json',
      );
      final s2OldFile = File(
        '$projDir${sep}ux${sep}screens${sep}scr-002-ecran-a-supprimer.json',
      );

      expect(await j1OldFile.exists(), isTrue);
      expect(await j2OldFile.exists(), isTrue);
      expect(await s1OldFile.exists(), isTrue);
      expect(await s2OldFile.exists(), isTrue);

      // Sauvegarde incrémentale : renommage de j1 et s1 + suppression de j2 et s2
      final updated = initial.copyWith(
        uxSpec: initial.uxSpec.copyWith(
          journeys: [
            j1.copyWith(code: 'JRN-010', name: 'Parcours Renommé Terrain'),
          ],
          screens: [
            s1.copyWith(code: 'SCR-010', name: 'Console Terrain Unifiée'),
          ],
        ),
      );
      await store.saveProject(updated);

      final j1NewFile = File(
        '$projDir${sep}ux${sep}journeys${sep}jrn-010-parcours-renomme-terrain.json',
      );
      final s1NewFile = File(
        '$projDir${sep}ux${sep}screens${sep}scr-010-console-terrain-unifiee.json',
      );

      expect(await j1OldFile.exists(), isFalse);
      expect(await j2OldFile.exists(), isFalse);
      expect(await s1OldFile.exists(), isFalse);
      expect(await s2OldFile.exists(), isFalse);
      expect(await j1NewFile.exists(), isTrue);
      expect(await s1NewFile.exists(), isTrue);

      final summaries = await store.listProjects();
      expect(summaries.single.journeyCount, 1);
      expect(summaries.single.screenCount, 1);
      expect(summaries.single.currentUxStage, UxForgeStage.uxReviewExport);

      final reloaded = await SpecProjectStore(tempDir)
          .loadProject('proj_fieldops');
      expect(reloaded, equals(updated));
    });

    test('projet v3 existant sans dossier ux/ se charge avec UxForgeSpec.empty et ne crée pas ux/ tant qu’aucun contenu UX n’est ajouté', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_v3_noux_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final projDir = Directory(
        '${tempDir.path}${sep}projects${sep}legacy-v3-app',
      );
      await Directory('${projDir.path}${sep}spec').create(recursive: true);
      await Directory('${projDir.path}${sep}chats').create(recursive: true);

      // Construction d'un dossier projet v3 préexistant antérieur au volet UX (sans ux/ ni clés UX dans project.json)
      await File('${projDir.path}${sep}project.json').writeAsString(
        SpecStorageIo.encodePrettyJson({
          'format': SpecProjectStore.manifestFormat,
          'version': SpecProjectStore.storageVersion,
          'id': 'proj_legacy_v3',
          'name': 'Legacy V3 App',
          'initialIdea': 'Gestion documentaire interne',
          'createdAt': '2026-05-10T08:00:00.000Z',
          'updatedAt': '2026-05-10T09:00:00.000Z',
          'currentStage': 'specifications',
        }),
      );
      await File('${projDir.path}${sep}spec${sep}lexicon.json').writeAsString(
        SpecStorageIo.encodePrettyJson({
          'format': 'super_spec_forge.lexicon',
          'version': SpecProjectStore.storageVersion,
          'data': {
            'terms': [
              {
                'id': 't_doc',
                'term': 'Document',
                'definition': 'Pièce archivée',
              },
            ],
          },
        }),
      );

      final store = SpecProjectStore(tempDir);
      final uxDir = Directory('${projDir.path}${sep}ux');
      final uxJourneyChatFile = File(
        '${projDir.path}${sep}chats${sep}ux_userJourneys.json',
      );

      expect(await uxDir.exists(), isFalse);
      expect(await uxJourneyChatFile.exists(), isFalse);

      // 1. Chargement propre avec UxForgeSpec.empty
      final loaded = await store.loadProject('proj_legacy_v3');
      expect(loaded, isNotNull);
      expect(loaded!.uxSpec, equals(UxForgeSpec.empty));
      expect(loaded.uxSpec.hasContent, isFalse);
      expect(await uxDir.exists(), isFalse);

      final initialSummaries = await store.listProjects();
      expect(initialSummaries.single.journeyCount, 0);
      expect(initialSummaries.single.screenCount, 0);
      expect(initialSummaries.single.currentUxStage, UxForgeStage.userJourneys);

      // 2. Sauvegarde incrémentale purement métier : toujours aucun fichier sous ux/ ni chats/ux_*.json
      final specOnlyUpdate = loaded.copyWith(
        vision: loaded.vision.copyWith(
          problemStatement: 'Classement manuel lent',
        ),
      );
      await store.saveProject(specOnlyUpdate);
      expect(await uxDir.exists(), isFalse);
      expect(await uxJourneyChatFile.exists(), isFalse);

      // 3. Dès qu'un contenu UX est ajouté, ux/ et chats/ux_*.json sont initialisés proprement
      final withUx = specOnlyUpdate.copyWith(
        uxSpec: UxForgeSpec(
          currentStage: UxForgeStage.userJourneys,
          journeys: [
            UxJourneySpec(
              id: 'jrn_archivage',
              code: 'JRN-001',
              name: 'Archivage rapide',
            ),
          ],
        ),
      );
      await store.saveProject(withUx);

      expect(await uxDir.exists(), isTrue);
      expect(await File('${uxDir.path}${sep}navigation.json').exists(), isTrue);
      expect(
        await File('${uxDir.path}${sep}coherence_issues.json').exists(),
        isTrue,
      );
      expect(
        await File(
          '${uxDir.path}${sep}journeys${sep}jrn-001-archivage-rapide.json',
        ).exists(),
        isTrue,
      );
      expect(await uxJourneyChatFile.exists(), isTrue);

      final reloadedWithUx = await SpecProjectStore(tempDir)
          .loadProject('proj_legacy_v3');
      expect(reloadedWithUx, equals(withUx));
    });
  });
}
