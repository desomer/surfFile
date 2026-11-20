import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  SpecForgeProject buildSampleProject() {
    final base = SpecForgeProject.fromIdea(
      idea: 'Plateforme de gestion de commandes B2B',
      name: 'B2B Orders',
    );
    return base.copyWith(
      vision: base.vision.copyWith(
        problemStatement: 'Commandes saisies par email sans contrôle.',
        valueProposition: 'Portail unifié avec validation automatique.',
        objectives: const ['Zéro erreur de facturation'],
        personas: [
          SpecPersona(
            id: 'p_acheteur',
            name: 'Acheteur',
            role: 'Passe les commandes',
          ),
        ],
      ),
      cahierDesCharges: SpecCahierDesCharges(
        modules: const [
          SpecModule(id: 'mod_cmd', name: 'Commandes'),
        ],
        functionalRequirements: [
          FunctionalRequirement(
            id: 'req_1',
            code: 'EXF-001',
            title: 'Création de commande',
            moduleId: 'mod_cmd',
            actorIds: const ['p_acheteur'],
            acceptanceCriteria: const ['Le total est calculé'],
          ),
        ],
      ),
      businessObjects: [
        BusinessObjectSpec(
          id: 'obj_commande',
          name: 'Commande',
          technicalName: 'Commande',
          description: 'Commande client B2B',
          attributes: [
            BusinessAttribute(
              id: 'a_ref',
              name: 'reference',
              type: BusinessAttributeType.string,
              required: true,
            ),
            BusinessAttribute(
              id: 'a_date',
              name: 'dateCreation',
              type: BusinessAttributeType.date,
              required: true,
            ),
            BusinessAttribute(
              id: 'a_statut',
              name: 'statut',
              type: BusinessAttributeType.enumeration,
              required: true,
              enumValues: const ['brouillon', 'validee'],
            ),
          ],
          lifecycleStates: const [
            LifecycleState(name: 'brouillon', isInitial: true),
            LifecycleState(name: 'validee', isTerminal: true),
          ],
          lifecycleTransitions: const [
            LifecycleTransition(
              id: 'tr_1',
              fromState: 'brouillon',
              toState: 'validee',
              trigger: 'Validation',
            ),
          ],
        ),
      ],
      businessRules: [
        BusinessRuleSpec(
          id: 'rg_1',
          code: 'RG-001',
          title: 'Validation commande',
          category: BusinessRuleCategory.stateTransition,
          targetObjectIds: const ['obj_commande'],
          trigger: 'Clic sur Valider',
          condition: 'statut == brouillon',
          effect: 'statut = validee',
        ),
      ],
    );
  }

  group('SpecCoherenceAnalyzer', () {
    test('ne détecte aucune anomalie sur un projet cohérent', () {
      final issues = SpecCoherenceAnalyzer.analyze(buildSampleProject());
      expect(issues, isEmpty);
    });

    test('détecte les références cassées sur règles, relations et transitions', () {
      final base = buildSampleProject();
      final broken = base.copyWith(
        businessObjects: [
          base.businessObjects.single.copyWith(
            relations: const [
              BusinessRelation(
                id: 'rel_1',
                name: 'client',
                targetObjectId: 'obj_inexistant',
              ),
            ],
            lifecycleTransitions: const [
              LifecycleTransition(
                id: 'tr_bad',
                fromState: 'brouillon',
                toState: 'etat_inconnu',
              ),
            ],
          ),
        ],
        businessRules: [
          ...base.businessRules,
          BusinessRuleSpec(
            id: 'rg_bad',
            code: 'RG-099',
            title: 'Cible absente',
            targetObjectIds: const ['obj_fantome'],
          ),
        ],
      );

      final issues = SpecCoherenceAnalyzer.analyze(broken);
      final codes = issues.map((i) => i.code).toSet();
      expect(codes, containsAll(['COH-OBJ-005', 'COH-OBJ-007', 'COH-RG-004']));
    });
  });

  group('Exporters & SpecProjectStore', () {
    test('SpecMarkdownExporter génère les sections, Mermaid et RG-001', () {
      final md = SpecMarkdownExporter.export(buildSampleProject());
      expect(md, contains('# Cahier des charges — B2B Orders'));
      expect(md, contains('erDiagram'));
      expect(md, contains('stateDiagram-v2'));
      expect(md, contains('RG-001 — Validation commande'));
      expect(md, contains('EXF-001'));
    });

    test('SpecSuperDesignerExporter génère YAML valide, JSON Schema et dossier sandboxé', () async {
      final project = buildSampleProject();
      final yamlText = SpecSuperDesignerExporter.toYamlLightSchema(project);
      final parsedYaml = loadYaml(yamlText) as YamlMap;
      expect(parsedYaml.containsKey('Commande'), isTrue);
      expect(yamlText, contains('reference: string!'));
      expect(yamlText, contains('statut: enum(brouillon, validee)!'));

      final bundle = SpecSuperDesignerExporter.toBundle(project);
      expect(bundle.repositoriesJsonSchemas.containsKey('commande'), isTrue);
      final schema = bundle.repositoriesJsonSchemas['commande']!;
      final seed = bundle.repositoriesSeedData['commande']!;
      expect(
        JsonSchemaValidator.validate(seed, schema).isValid,
        isTrue,
      );

      final tempDir = await Directory.systemTemp.createTemp('spec_forge_sd_');
      try {
        final appDir = Directory('${tempDir.path}${Platform.pathSeparator}app');
        final manifest =
            await SpecSuperDesignerExporter.exportToSandboxedApplication(
          project,
          appDir,
        );
        expect(manifest.name, 'B2B Orders');
        expect(
          await File('${appDir.path}${Platform.pathSeparator}app.json').exists(),
          isTrue,
        );
        expect(
          await File('${appDir.path}${Platform.pathSeparator}spec_forge_schema.yaml')
              .exists(),
          isTrue,
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('SpecProjectStore sauvegarde, liste, recharge et supprime', () async {
      final tempDir = await Directory.systemTemp.createTemp('spec_forge_store_');
      try {
        final store = SpecProjectStore(tempDir);
        final project = buildSampleProject();
        await store.saveProject(project);

        final list = await store.listProjects();
        expect(list.length, 1);
        expect(list.single.name, 'B2B Orders');

        final loaded = await store.loadProject(project.id);
        expect(loaded, equals(project));

        expect(await store.getLastActiveProjectId(), project.id);

        await store.deleteProject(project.id);
        expect(await store.listProjects(), isEmpty);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
