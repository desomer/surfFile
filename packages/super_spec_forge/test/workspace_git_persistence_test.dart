import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecStorageSlug & SpecStorageIo', () {
    test('génère des slugs lisibles sans accents et protégés Windows', () {
      expect(
        SpecStorageSlug.slugify('Gestion de flotte — Véhicules'),
        'gestion-de-flotte-vehicules',
      );
      expect(
        SpecStorageSlug.slugify('DeliveryNoteLine', separator: '_'),
        'delivery_note_line',
      );
      expect(SpecStorageSlug.slugify('CON', fallback: 'obj'), 'obj-con');
      expect(SpecStorageSlug.slugify('nul', fallback: 'item'), 'item-nul');
      expect(SpecStorageSlug.slugify('   ', fallback: 'project'), 'project');
    });

    test('résout les collisions de noms de fichiers de manière déterministe', () {
      final assigned = SpecStorageSlug.assignUniqueJsonFiles<({String id, String name})>(
        [
          (id: 'id_alpha_1', name: 'Commande'),
          (id: 'id_beta_2', name: 'Commande'),
        ],
        labelFor: (e) => e.name,
        idFor: (e) => e.id,
      );
      expect(assigned.keys.toList(), [
        'commande.json',
        'commande__idbeta2.json',
      ]);
    });

    test('encodePrettyJson garantit LF sans CRLF et newline finale', () {
      final encoded = SpecStorageIo.encodePrettyJson({
        'title': 'Ligne 1\r\nLigne 2',
      });
      expect(encoded.contains('\r'), isFalse);
      expect(encoded.endsWith('\n'), isTrue);
      expect(encoded.endsWith('\n\n'), isFalse);
    });
  });

  group('Persistance v3 découpée par dossier (Git-friendly)', () {
    test('SpecProjectStore découpe objets/règles, met à jour incrémentalement et élague les renommages', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_split_v3_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final store = SpecProjectStore(tempDir);
      final obj1 = BusinessObjectSpec(
        id: 'obj_1',
        name: 'Véhicule',
        technicalName: 'Vehicle',
      );
      final obj2 = BusinessObjectSpec(
        id: 'obj_2',
        name: 'Réservation',
        technicalName: 'Reservation',
      );
      final rule1 = BusinessRuleSpec(
        id: 'r_1',
        code: 'RG-001',
        title: 'Disponibilité véhicule',
      );
      final rule2 = BusinessRuleSpec(
        id: 'r_2',
        code: 'RG-002',
        title: 'Kilométrage positif',
      );

      final project = SpecForgeProject.fromIdea(
        idea: 'Suivi de flotte',
        name: 'Flotte Auto',
        id: 'proj_flotte',
      ).copyWith(
        businessObjects: [obj2, obj1],
        businessRules: [rule1, rule2],
      );

      await store.saveProject(project);

      final projDir = '${tempDir.path}${sep}projects${sep}flotte-auto';
      final obj1File = File(
        '$projDir${sep}spec${sep}business_objects${sep}vehicle.json',
      );
      final obj2File = File(
        '$projDir${sep}spec${sep}business_objects${sep}reservation.json',
      );
      final rule1File = File(
        '$projDir${sep}spec${sep}business_rules${sep}rg-001-disponibilite-vehicule.json',
      );
      final rule2File = File(
        '$projDir${sep}spec${sep}business_rules${sep}rg-002-kilometrage-positif.json',
      );

      expect(await obj1File.exists(), isTrue);
      expect(await obj2File.exists(), isTrue);
      expect(await rule1File.exists(), isTrue);
      expect(await rule2File.exists(), isTrue);

      // L'ordre initial [obj2, obj1] est préservé au rechargement grâce à _order.json.
      final loaded = await store.loadProject('proj_flotte');
      expect(loaded, isNotNull);
      expect(loaded!.businessObjects.map((o) => o.id).toList(), ['obj_2', 'obj_1']);
      expect(loaded.businessRules.map((r) => r.id).toList(), ['r_1', 'r_2']);

      // Modification d'un seul objet : l'autre fichier objet et les règles ne sont pas réécrits.
      final past = DateTime(2020, 1, 1);
      obj1File.setLastModifiedSync(past);
      obj2File.setLastModifiedSync(past);
      rule1File.setLastModifiedSync(past);

      final updatedObj1 = project.copyWith(
        businessObjects: [
          obj2,
          obj1.copyWith(description: 'Véhicule immatriculé'),
        ],
      );
      await store.saveProject(updatedObj1);

      expect(obj1File.lastModifiedSync().isAfter(past), isTrue);
      expect(obj2File.lastModifiedSync(), equals(past));
      expect(rule1File.lastModifiedSync(), equals(past));

      // Renommage de obj1 et suppression de rule2 : anciens fichiers supprimés proprement.
      final renamed = updatedObj1.copyWith(
        businessObjects: [
          obj2,
          obj1.copyWith(technicalName: 'FleetVehicle'),
        ],
        businessRules: [rule1],
      );
      await store.saveProject(renamed);

      expect(await obj1File.exists(), isFalse);
      expect(
        await File(
          '$projDir${sep}spec${sep}business_objects${sep}fleet_vehicle.json',
        ).exists(),
        isTrue,
      );
      expect(await rule2File.exists(), isFalse);

      final summaries = await store.listProjects();
      expect(summaries.single.objectCount, 2);
      expect(summaries.single.ruleCount, 1);
    });

    test('CompanyGlossaryStore et ModelDictionaryStore découpent termes et règles', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_refs_v3_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final glossaryStore = CompanyGlossaryStore(tempDir);
      final termA = CompanyGlossaryTerm(id: 'cg_a', term: 'Bon de livraison');
      final termB = CompanyGlossaryTerm(id: 'cg_b', term: 'Avoir client');
      await glossaryStore.saveGlossary(
        CompanyGlossary(
          terms: [termA, termB],
          conventions: const ['EUR HT'],
        ),
      );

      final termAFile = File(
        '${tempDir.path}${sep}glossary${sep}terms${sep}bon-de-livraison.json',
      );
      final termBFile = File(
        '${tempDir.path}${sep}glossary${sep}terms${sep}avoir-client.json',
      );
      expect(await termAFile.exists(), isTrue);
      expect(await termBFile.exists(), isTrue);
      expect(
        await File('${tempDir.path}${sep}glossary${sep}glossary.json').exists(),
        isTrue,
      );

      final past = DateTime(2020, 1, 1);
      termAFile.setLastModifiedSync(past);
      termBFile.setLastModifiedSync(past);

      await glossaryStore.saveGlossary(
        CompanyGlossary(
          terms: [termA.copyWith(definition: 'Remise au client'), termB],
          conventions: const ['EUR HT'],
        ),
      );
      expect(termAFile.lastModifiedSync().isAfter(past), isTrue);
      expect(termBFile.lastModifiedSync(), equals(past));

      final dictStore = ModelDictionaryStore(tempDir);
      final customRule = const TechnicalModelingRule(
        id: 'rule_custom_iban',
        name: 'IBAN Fournisseur',
        suffixOrPattern: '*Iban',
        category: TechnicalRuleCategory.custom,
        whenToUse: 'Compte bancaire fournisseur.',
      );
      final prefs = BusinessObjectModelPreferences.defaults.copyWith(
        technicalRules: [...TechnicalModelingRule.defaultRules, customRule],
      );
      await dictStore.save(prefs);

      expect(
        await File('${tempDir.path}${sep}dictionary${sep}preferences.json')
            .exists(),
        isTrue,
      );
      expect(
        await File(
          '${tempDir.path}${sep}dictionary${sep}rules${sep}iban-fournisseur.json',
        ).exists(),
        isTrue,
      );
      expect(await dictStore.load(), equals(prefs));
    });
  });

  group('SpecWorkspaceStore & bascule de workspace', () {
    test('initialise workspace.json + .gitignore, tolère .git et protège les dossiers non vides', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_ws_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final wsStore = SpecWorkspaceStore(usePreferences: false);

      // Un dossier contenant uniquement .git est considéré comme initialisable.
      final gitRepoDir = Directory('${tempDir.path}${sep}mon-depot-specs');
      await Directory('${gitRepoDir.path}$sep.git').create(recursive: true);
      final meta = await wsStore.openWorkspace(gitRepoDir);
      expect(meta.name, 'mon-depot-specs');
      expect(
        await SpecWorkspaceStore.metadataFileFor(gitRepoDir).exists(),
        isTrue,
      );
      final gitignore = await SpecWorkspaceStore.gitignoreFileFor(
        gitRepoDir,
      ).readAsString();
      expect(gitignore, contains('.local/'));
      expect(gitignore, contains('exports/'));
      expect(gitignore.contains('\r\n'), isFalse);

      // Ne pas écraser un .gitignore personnalisé existant.
      await SpecWorkspaceStore.gitignoreFileFor(
        gitRepoDir,
      ).writeAsString('# custom\n.local/\n');
      await wsStore.openWorkspace(gitRepoDir);
      expect(
        await SpecWorkspaceStore.gitignoreFileFor(gitRepoDir).readAsString(),
        '# custom\n.local/\n',
      );

      // Dossier non vide inconnu -> NonEmptyNonWorkspaceException sauf confirmation.
      final nonEmptyDir = Directory('${tempDir.path}${sep}existing-files');
      await nonEmptyDir.create(recursive: true);
      await File('${nonEmptyDir.path}${sep}notes.txt').writeAsString('hello');
      await expectLater(
        () => wsStore.openWorkspace(nonEmptyDir),
        throwsA(isA<NonEmptyNonWorkspaceException>()),
      );

      final forcedMeta = await wsStore.openWorkspace(
        nonEmptyDir,
        initializeNonEmpty: true,
        defaultName: 'Dépôt initialisé',
      );
      expect(forcedMeta.name, 'Dépôt initialisé');
    });

    test('SpecForgeController.switchWorkspace isole projets, glossaire et dictionnaire par dossier', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_ctrl_ws_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final wsA = Directory('${tempDir.path}${sep}repo-a');
      final wsB = Directory('${tempDir.path}${sep}repo-b');
      final wsStore = SpecWorkspaceStore(
        fallbackRootDirectory: wsA,
        usePreferences: false,
      );

      final controller = SpecForgeController(workspaceStore: wsStore);
      addTearDown(controller.dispose);

      await controller.initialize(restoreLastProject: false);
      expect(controller.workspaceDirectory.path, wsA.path);

      await controller.createProjectFromIdea(
        idea: 'Application A',
        name: 'Projet Alpha',
      );
      await controller.upsertCompanyGlossaryTerm(
        CompanyGlossaryTerm(id: 'cg_a', term: 'Terme A'),
      );
      expect(controller.recentProjects.length, 1);

      await controller.createWorkspace(wsB, name: 'Repo B');
      expect(controller.workspaceDirectory.path, wsB.path);
      expect(controller.project, isNull);
      expect(controller.recentProjects, isEmpty);
      expect(controller.companyGlossary.terms, isEmpty);

      await controller.createProjectFromIdea(
        idea: 'Application B',
        name: 'Projet Beta',
      );
      expect(controller.recentProjects.single.name, 'Projet Beta');

      // Retour sur repo-a : restaure Projet Alpha et Terme A.
      await controller.switchWorkspace(wsA, restoreLastProject: true);
      expect(controller.project?.name, 'Projet Alpha');
      expect(controller.companyGlossary.terms.single.term, 'Terme A');
    });

    testWidgets('SpecWorkspaceSelectorDialog permet de créer et ouvrir un workspace via pickDirectory', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final sep = Platform.pathSeparator;
      late Directory tempDir;
      late Directory wsInitial;
      late Directory wsNew;
      late SpecForgeController controller;

      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('ssf_ui_ws_');
        wsInitial = Directory('${tempDir.path}${sep}ws-initial');
        wsNew = Directory('${tempDir.path}${sep}ws-nouveau');
        controller = SpecForgeController(
          workspaceStore: SpecWorkspaceStore(
            fallbackRootDirectory: wsInitial,
            usePreferences: false,
          ),
        );
        await controller.initialize(restoreLastProject: false);
      });
      addTearDown(() async {
        controller.dispose();
        await tester.runAsync(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SpecForgeShell(
            controller: controller,
            pickDirectory: (_) async => wsNew.path,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('spec-workspace-selector-btn')));
      await tester.pumpAndSettle();

      expect(find.text('Dossier Workspace (dépôt Git)'), findsOneWidget);

      await tester.tap(find.text('Nouveau'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('workspace-create-name-field')),
        'Nouveau Dépôt',
      );
      await tester.tap(find.byKey(const ValueKey('workspace-create-browse-btn')));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('workspace-create-submit-btn')));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (controller.workspaceDirectory.path != wsNew.path &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(controller.workspaceDirectory.path, wsNew.path);
      expect(controller.workspaceMetadata?.name, 'Nouveau Dépôt');
      expect(
        SpecWorkspaceStore.gitignoreFileFor(wsNew).existsSync(),
        isTrue,
      );
    });
  });
}
