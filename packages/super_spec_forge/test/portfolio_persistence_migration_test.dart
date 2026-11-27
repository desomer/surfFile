import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecProjectStore v4 — Initiatives/Features & Migration v3', () {
    test(
      'migre automatiquement un projet v3 sur disque (sans dossier initiatives/) vers Initiative principale > Feature initiale',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ssf_mig_v3_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final sep = Platform.pathSeparator;
        final projDir = Directory('${tempDir.path}${sep}projects${sep}crm-b2b');
        await Directory('${projDir.path}${sep}spec${sep}business_objects')
            .create(recursive: true);
        await Directory('${projDir.path}${sep}chats').create(recursive: true);

        await SpecStorageIo.writeJsonAtomicallyIfChanged(
          File('${projDir.path}${sep}project.json'),
          <String, Object?>{
            'format': SpecProjectStore.manifestFormat,
            'version': 3,
            'id': 'proj_legacy_v3',
            'name': 'CRM B2B Legacy',
            'initialIdea': 'Pipeline commercial B2B',
            'createdAt': '2026-01-10T10:00:00.000Z',
            'updatedAt': '2026-01-10T12:00:00.000Z',
            'currentStage': 'businessObjects',
          },
          nextTmpId: () => 1,
        );

        await SpecStorageIo.writeJsonAtomicallyIfChanged(
          File('${projDir.path}${sep}spec${sep}lexicon.json'),
          <String, Object?>{
            'format': 'super_spec_forge.lexicon',
            'version': 3,
            'data': SpecLexicon(
              terms: [
                LexiconTerm(
                  id: 't_opp',
                  term: 'Opportunité',
                  definition: 'Affaire commerciale qualifiée',
                ),
              ],
            ).toJson(),
          },
          nextTmpId: () => 2,
        );

        await SpecStorageIo.writeJsonAtomicallyIfChanged(
          File(
            '${projDir.path}${sep}spec${sep}business_objects${sep}opportunity.json',
          ),
          <String, Object?>{
            'format': SpecProjectStore.businessObjectFormat,
            'version': 3,
            'data': BusinessObjectSpec(
              id: 'obj_opp',
              name: 'Opportunité',
              technicalName: 'Opportunity',
            ).toJson(),
          },
          nextTmpId: () => 3,
        );

        final store = SpecProjectStore(tempDir);
        final loaded = await store.loadProject('proj_legacy_v3');
        expect(loaded, isNotNull);
        expect(loaded!.initiatives.length, 1);
        expect(loaded.initiatives.single.id, SpecInitiative.defaultInitiativeId);
        expect(loaded.activeFeature.id, SpecFeatureSpec.defaultFeatureId);
        expect(loaded.currentStage, SpecForgeStage.businessObjects);
        expect(loaded.lexicon.terms.single.term, 'Opportunité');
        expect(loaded.businessObjects.single.technicalName, 'Opportunity');
      },
    );

    test(
      'persiste plusieurs initiatives et features dans initiatives/<slug>/features/<slug>/, gère les suppressions et met à jour SpecProjectSummary',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('ssf_port_v4_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final sep = Platform.pathSeparator;
        final store = SpecProjectStore(tempDir);

        final featCatalog = SpecFeatureSpec.create(
          id: 'feat_cat',
          code: 'FEAT-01',
          name: 'Catalogue Produits',
          description: 'Gestion des articles et tarifs',
          targetRelease: 'MVP',
        ).copyWith(
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_prod',
              name: 'Produit',
              technicalName: 'Product',
            ),
          ],
        );

        final featCheckout = SpecFeatureSpec.create(
          id: 'feat_chk',
          code: 'FEAT-02',
          name: 'Panier & Paiement',
          description: 'Tunnel d’achat et paiement CB',
          targetRelease: 'MVP',
        ).copyWith(
          businessObjects: [
            BusinessObjectSpec(
              id: 'obj_cart',
              name: 'Panier',
              technicalName: 'Cart',
            ),
            BusinessObjectSpec(
              id: 'obj_pay',
              name: 'Paiement',
              technicalName: 'Payment',
            ),
          ],
          businessRules: [
            BusinessRuleSpec(
              id: 'rg_min',
              code: 'RG-010',
              title: 'Montant minimum de commande',
            ),
          ],
          costSpec: CostForgeSpec(
            wbsItems: [
              CostWbsItemSpec(
                id: 'wbs_1',
                code: 'WBS-01',
                title: 'Intégration Stripe',
                discipline: CostDiscipline.backend,
                optimisticDays: 3,
                mostLikelyDays: 5,
                pessimisticDays: 8,
              ),
            ],
          ),
        );

        final featReturns = SpecFeatureSpec.create(
          id: 'feat_ret',
          code: 'FEAT-03',
          name: 'Gestion des retours SAV',
          targetRelease: 'Lot 2',
          priority: RequirementPriority.should,
        );

        final project = SpecForgeProject.fromIdea(
          id: 'proj_shop',
          name: 'OmniShop',
          idea: 'Plateforme e-commerce omnicanale',
        ).copyWith(
          lexicon: SpecLexicon(
            terms: [
              LexiconTerm(id: 't_sku', term: 'SKU', definition: 'Référence article'),
            ],
          ),
          portfolioChatMessages: [
            SpecChatMessage(
              id: 'pf_1',
              isUser: true,
              text: 'Découpe OmniShop en 2 initiatives',
            ),
          ],
          initiatives: [
            SpecInitiative.create(
              id: 'init_vente',
              code: 'INIT-01',
              name: 'Vente en ligne',
              features: [featCatalog, featCheckout],
            ),
            SpecInitiative.create(
              id: 'init_sav',
              code: 'INIT-02',
              name: 'Après-vente',
              priority: RequirementPriority.should,
              features: [featReturns],
            ),
          ],
          activeFeatureId: 'feat_chk',
        );

        await store.saveProject(project);

        final projPath = '${tempDir.path}${sep}projects${sep}omni-shop';
        expect(
          await File('$projPath${sep}initiatives${sep}_order.json').exists(),
          isTrue,
        );
        expect(
          await File(
            '$projPath${sep}chats${sep}portfolio_chat.json',
          ).exists(),
          isTrue,
        );
        expect(
          await File(
            '$projPath${sep}initiatives${sep}init-01-vente-en-ligne${sep}features${sep}feat-02-panier-paiement${sep}spec${sep}business_objects${sep}payment.json',
          ).exists(),
          isTrue,
        );

        // Vérification du résumé listProjects().
        final summaries = await store.listProjects();
        expect(summaries.length, 1);
        expect(summaries.single.initiativeCount, 2);
        expect(summaries.single.specFeatureCount, 3);
        expect(summaries.single.activeFeatureName, 'Panier & Paiement');
        expect(summaries.single.objectCount, 3);
        expect(summaries.single.ruleCount, 1);

        // Rechargement complet dans une nouvelle instance de store.
        final freshStore = SpecProjectStore(tempDir);
        final reloaded = await freshStore.loadProject('proj_shop');
        expect(reloaded, isNotNull);
        expect(reloaded, equals(project));

        // Suppression de la 2e initiative : son sous-dossier est élagué proprement.
        final withoutSav = reloaded!.copyWith(
          initiatives: [reloaded.initiatives.first],
        );
        await freshStore.saveProject(withoutSav);
        expect(
          await Directory(
            '$projPath${sep}initiatives${sep}init-02-apres-vente',
          ).exists(),
          isFalse,
        );
      },
    );
  });
}
