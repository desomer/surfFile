import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('CompanyGlossary modèles & validations', () {
    test('round-trip JSON complet, conversions LexiconTerm et validation', () {
      final now = DateTime.utc(2026, 11, 21, 9, 30);
      final term = CompanyGlossaryTerm(
        id: 'cg_bl',
        term: 'Bon de livraison',
        definition: 'Document attestant la remise physique au client.',
        synonyms: const ['BL', 'Bordereau', 'bl'],
        forbiddenTerms: const ['Ticket sortie', 'Bon client'],
        domain: 'Logistique',
        owner: 'Direction Supply Chain',
        technicalNameHint: 'DeliveryNote',
        examples: const ['BL-2026-0001 signé'],
        status: CompanyGlossaryStatus.approved,
        createdAt: now,
        updatedAt: now,
      );

      final glossary = CompanyGlossary(
        terms: [term],
        conventions: const ['Montants en EUR HT'],
        ambiguousTerms: const ['Client (facturé vs livré)'],
        updatedAt: now,
      );
      glossary.validate();

      // Déduplication insensible à la casse des synonymes.
      expect(term.synonyms, ['BL', 'Bordereau']);

      // Round-trip JSON.
      final decoded = CompanyGlossary.fromJson(glossary.toJson());
      expect(decoded, glossary);

      // Conversion vers/depuis LexiconTerm.
      final lex = term.toLexiconTerm();
      expect(lex.term, 'Bon de livraison');
      expect(lex.synonyms, containsAll(['BL', 'Bordereau', 'Ticket sortie']));
      final back = CompanyGlossaryTerm.fromLexiconTerm(lex, now: now);
      expect(back.status, CompanyGlossaryStatus.approved);
      expect(back.term, 'Bon de livraison');

      // Rejet des IDs dupliqués.
      expect(
        () => CompanyGlossary(terms: [term, term]).validate(),
        throwsFormatException,
      );

      // upsertTerm renseigne createdAt/updatedAt à l'ajout et préserve createdAt à la mise à jour.
      final createdAt = DateTime.utc(2026, 11, 20, 8, 0);
      final updatedAt = DateTime.utc(2026, 11, 21, 14, 15);
      final added = CompanyGlossary.empty.upsertTerm(
        CompanyGlossaryTerm(id: 'cg_t', term: 'Tiers'),
        now: createdAt,
      );
      expect(added.terms.single.createdAt, createdAt);
      expect(added.terms.single.updatedAt, createdAt);
      expect(added.updatedAt, createdAt);

      final modified = added.upsertTerm(
        CompanyGlossaryTerm(
          id: 'cg_t',
          term: 'Tiers',
          definition: 'Personne physique ou morale.',
        ),
        now: updatedAt,
      );
      expect(modified.terms.single.createdAt, createdAt);
      expect(modified.terms.single.updatedAt, updatedAt);
      expect(modified.updatedAt, updatedAt);
    });
  });

  group('CompanyGlossaryStore persistance disque', () {
    test('sauvegarde atomique et rechargement glossaire + chat', () async {
      final tempDir = await Directory.systemTemp.createTemp('cg_store_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = CompanyGlossaryStore(tempDir);
      expect(await store.loadGlossary(), CompanyGlossary.empty);

      final glossary = CompanyGlossary(
        terms: [
          CompanyGlossaryTerm(
            id: 'cg_cmd',
            term: 'Commande client',
            definition: 'Engagement ferme d’achat.',
            forbiddenTerms: const ['Ordre client'],
            domain: 'Ventes',
            status: CompanyGlossaryStatus.approved,
          ),
        ],
        conventions: const ['Codes ISO 4217 pour les devises'],
      );
      await store.saveGlossary(glossary);
      await store.saveChatMessages([
        SpecChatMessage(id: 'm1', isUser: true, text: 'Analyse ce glossaire'),
      ]);

      final reloadedStore = CompanyGlossaryStore(tempDir);
      final loaded = await reloadedStore.loadGlossary();
      final loadedChat = await reloadedStore.loadChatMessages();

      expect(loaded, glossary);
      expect(loadedChat.length, 1);
      expect(loadedChat.first.text, 'Analyse ce glossaire');
    });
  });

  group('CompanyGlossaryCodec import/export', () {
    test('export JSON / Markdown / CSV et prévisualisation de fusion', () {
      final createdAt = DateTime.utc(2026, 11, 20, 10, 15);
      final updatedAt = DateTime.utc(2026, 11, 21, 11, 30);
      final current = CompanyGlossary(
        terms: [
          CompanyGlossaryTerm(
            id: 'cg_devis',
            term: 'Devis',
            definition: 'Offre chiffrée.',
            synonyms: const ['Chiffrage'],
            forbiddenTerms: const ['Estimation volante'],
            domain: 'Commercial',
            owner: 'ADV',
            technicalNameHint: 'Quote',
            status: CompanyGlossaryStatus.approved,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        ],
        conventions: const ['Montants HT'],
        updatedAt: updatedAt,
      );

      final jsonStr = CompanyGlossaryCodec.toJsonString(current);
      final parsedJson = CompanyGlossaryCodec.parseJson(jsonStr);
      expect(parsedJson.terms.single.term, 'Devis');
      expect(parsedJson.terms.single.createdAt, createdAt);
      expect(parsedJson.terms.single.updatedAt, updatedAt);

      final md = CompanyGlossaryCodec.toMarkdown(current);
      expect(md, contains('| **Devis** | Validé | Commercial |'));
      expect(md, contains('Estimation volante'));
      expect(md, contains('Ajouté le | Modifié le'));

      final csv = CompanyGlossaryCodec.toCsv(current);
      expect(csv, contains('term,status,domain'));
      expect(csv, contains('createdAt,updatedAt'));
      final parsedCsv = CompanyGlossaryCodec.parseCsv(csv);
      expect(parsedCsv.terms.single.term, 'Devis');
      expect(parsedCsv.terms.single.forbiddenTerms, ['Estimation volante']);
      expect(parsedCsv.terms.single.createdAt, createdAt);
      expect(parsedCsv.terms.single.updatedAt, updatedAt);

      // Fusion avec un CSV point-virgule contenant 1 mise à jour + 1 ajout.
      const incomingCsv =
          'term;status;domain;definition;synonyms;forbiddenTerms;owner;technicalNameHint\n'
          'Devis;approved;Commercial;;Proposition;;ADV;Quote\n'
          'Facture;draft;Finance;Pièce comptable client.;Fact.;Note de débit;Compta;Invoice\n';
      final incoming = CompanyGlossaryCodec.parseCsv(incomingCsv);
      final preview = CompanyGlossaryCodec.previewMerge(
        current: current,
        incoming: incoming,
      );

      expect(preview.addedTerms.length, 1);
      expect(preview.addedTerms.first.term, 'Facture');
      expect(preview.updatedTerms.length, 1);
      expect(preview.updatedTerms.first.synonyms, ['Chiffrage', 'Proposition']);
      expect(preview.mergedGlossary.terms.length, 2);
    });
  });

  group('Cohérence, prompts IA et passerelle projet <-> entreprise', () {
    test('SpecCoherenceAnalyzer détecte termes proscrits et dépréciés', () {
      final glossary = CompanyGlossary(
        terms: [
          CompanyGlossaryTerm(
            id: 'cg_cmd',
            term: 'Commande client',
            forbiddenTerms: const ['Bon d’achat interne'],
            technicalNameHint: 'CustomerOrder',
            status: CompanyGlossaryStatus.approved,
          ),
          CompanyGlossaryTerm(
            id: 'cg_old',
            term: 'Dossier papier',
            status: CompanyGlossaryStatus.deprecated,
          ),
        ],
      );

      final project = SpecForgeProject.fromIdea(
        idea: 'Suivi des commandes et dossiers',
      ).copyWith(
        lexicon: SpecLexicon(
          terms: [
            LexiconTerm(id: 'l1', term: 'Bon d’achat interne'),
            LexiconTerm(id: 'l2', term: 'Dossier papier'),
          ],
        ),
        businessObjects: [
          BusinessObjectSpec(
            id: 'o1',
            name: 'Bon d’achat interne',
            technicalName: 'BonAchat',
          ),
        ],
      );

      final issues = SpecCoherenceAnalyzer.analyze(
        project,
        companyGlossary: glossary,
      );
      expect(issues.where((i) => i.code == 'COH-LEX-004').length, 2);
      expect(issues.where((i) => i.code == 'COH-LEX-005').length, 1);
    });

    test('SpecPromptBuilder injecte le glossaire d’entreprise quand non vide', () {
      final glossary = CompanyGlossary(
        terms: [
          CompanyGlossaryTerm(
            id: 'cg_1',
            term: 'Bon de livraison',
            forbiddenTerms: const ['Ticket sortie'],
            status: CompanyGlossaryStatus.approved,
          ),
        ],
      );
      final project = SpecForgeProject.fromIdea(idea: 'Logistique entrepôt');
      final prompt = SpecPromptBuilder.buildTurnPrompt(
        project: project,
        stage: SpecForgeStage.lexicon,
        userInput: 'Démarre',
        questioningLevel: VibeQuestioningLevel.balanced,
        afterAskUserReply: false,
        companyGlossary: glossary,
      );
      expect(prompt, contains('GLOSSAIRE D’ENTREPRISE'));
      expect(prompt, contains('Bon de livraison'));
      expect(prompt, contains('Ticket sortie'));
    });

    test('SpecForgeController passerelle import <-> promotion et undo', () async {
      final tempDir = await Directory.systemTemp.createTemp('cg_ctrl_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final controller = SpecForgeController(
        store: SpecProjectStore(tempDir),
      );
      addTearDown(controller.dispose);
      await controller.initialize(restoreLastProject: false);

      await controller.upsertCompanyGlossaryTerm(
        CompanyGlossaryTerm(
          id: 'cg_client',
          term: 'Client',
          definition: 'Tiers acheteur facturé.',
          forbiddenTerms: const ['Compte tiers'],
          domain: 'Ventes',
          status: CompanyGlossaryStatus.approved,
        ),
      );
      expect(controller.companyGlossary.terms.length, 1);

      await controller.createProjectFromIdea(
        idea: 'Gestion des ventes B2B',
        autoKickoff: false,
      );
      final imported = await controller.importCompanyGlossaryToProject(
        termIds: const ['cg_client'],
      );
      expect(imported.added, 1);
      expect(imported.updated, 0);
      expect(controller.project!.lexicon.terms.single.term, 'Client');

      // Promotion d'un nouveau terme projet vers le glossaire d'entreprise.
      final promoted = await controller.promoteLexiconTermToCompanyGlossary(
        LexiconTerm(
          id: 'lex_avoir',
          term: 'Avoir',
          definition: 'Pièce annulant tout ou partie d’une facture.',
          domain: 'Finance',
        ),
      );
      expect(promoted.created, isTrue);
      expect(controller.companyGlossary.terms.length, 2);

      await controller.undoCompanyGlossary();
      expect(controller.companyGlossary.terms.length, 1);
      await controller.redoCompanyGlossary();
      expect(controller.companyGlossary.terms.length, 2);
    });

    test('CompanyGlossaryAiAgent.applyPatch ajoute, met à jour et supprime', () {
      final initial = CompanyGlossary(
        terms: [
          CompanyGlossaryTerm(
            id: 'cg_a',
            term: 'Ancien',
            status: CompanyGlossaryStatus.draft,
          ),
        ],
      );
      final res = CompanyGlossaryAiAgent.applyPatch(initial, {
        'terms': [
          {
            'id': 'cg_b',
            'term': 'Contrat',
            'definition': 'Accord signé.',
            'status': 'approved',
          },
        ],
        'removeTermIds': ['cg_a'],
        'conventions': ['Dates ISO 8601'],
      });
      expect(res.glossary.terms.length, 1);
      expect(res.glossary.terms.single.term, 'Contrat');
      expect(res.glossary.conventions, ['Dates ISO 8601']);
      expect(res.summary, contains('+1 terme(s)'));
    });
  });
}
