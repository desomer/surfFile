import 'dart:convert';
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
      lexicon: SpecLexicon(
        terms: [
          LexiconTerm(
            id: 't_cmd',
            term: 'Commande',
            definition: 'Demande d’achat validée par un acheteur B2B.',
            synonyms: const ['BC'],
            domain: 'Ventes',
          ),
        ],
      ),
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
      expect(md, contains('## 1. Lexique métier'));
      expect(md, contains('Demande d’achat validée'));
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

        // Migration automatique d'un ancien fichier JSON contenant un attribut accentué.
        final legacyProject = buildSampleProject();
        final legacyJson = legacyProject.toJson();
        final objs = (legacyJson['businessObjects'] as List).cast<Map<String, Object?>>();
        final attrs = (objs.first['attributes'] as List).cast<Map<String, Object?>>();
        attrs.add({
          'id': 'a_legacy_accent',
          'name': 'statutCohérence',
          'type': 'string',
          'required': true,
        });
        final legacyFile = File(
          '${tempDir.path}${Platform.pathSeparator}projects${Platform.pathSeparator}${legacyProject.id}${Platform.pathSeparator}project.json',
        );
        await legacyFile.parent.create(recursive: true);
        await legacyFile.writeAsString(jsonEncode(legacyJson));

        final migrated = await store.loadProject(legacyProject.id);
        expect(migrated, isNotNull);
        expect(
          migrated!.businessObjects.first.attributes.last.name,
          'statutCoherence',
        );
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
    test('SpecSuperDesignerExporter supporte les sous-objets imbriqués dans JSON Schema', () {
      final base = buildSampleProject();
      final structuredProject = base.copyWith(
        businessObjects: [
          base.businessObjects.single.copyWith(
            attributes: [
              ...base.businessObjects.single.attributes,
              BusinessAttribute(
                id: 'a_adr',
                name: 'adresseLivraison',
                type: BusinessAttributeType.object,
                required: true,
                children: [
                  BusinessAttribute(
                    id: 'a_ville',
                    name: 'ville',
                    type: BusinessAttributeType.string,
                    required: true,
                  ),
                ],
              ),
              BusinessAttribute(
                id: 'a_lignes',
                name: 'lignes',
                type: BusinessAttributeType.object,
                isArray: true,
                estimatedMaxRows: 50,
                children: [
                  BusinessAttribute(
                    id: 'a_qte',
                    name: 'quantite',
                    type: BusinessAttributeType.integer,
                    required: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final bundle = SpecSuperDesignerExporter.toBundle(structuredProject);
      final schema = bundle.repositoriesJsonSchemas['commande']!;
      final seed = bundle.repositoriesSeedData['commande']!;
      expect(JsonSchemaValidator.validate(seed, schema).isValid, isTrue);
      final itemProps =
          ((schema['properties'] as Map)['commandes'] as Map)['items'] as Map;
      final props = itemProps['properties'] as Map;
      expect((props['adresseLivraison'] as Map)['type'], 'object');
      expect((props['lignes'] as Map)['maxItems'], 50);
    });

    test('SpecSuperDesignerExporter exporte toutes les contraintes JSON Schema et valide le document', () {
      final base = buildSampleProject();
      final constrained = base.copyWith(
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_produit',
            name: 'Produit',
            technicalName: 'Produit',
            attributes: [
              BusinessAttribute(
                id: 'a_sku',
                name: 'sku',
                type: BusinessAttributeType.string,
                required: true,
                schemaConstraints: JsonSchemaConstraints(
                  minLength: 4,
                  maxLength: 20,
                  pattern: r'^[A-Z0-9-]+$',
                  examples: const ['PRD-001'],
                ),
              ),
              BusinessAttribute(
                id: 'a_prix',
                name: 'prixHt',
                type: BusinessAttributeType.number,
                required: true,
                schemaConstraints: JsonSchemaConstraints(
                  minimum: 1,
                  maximum: 100000,
                  multipleOf: 0.5,
                ),
              ),
              BusinessAttribute(
                id: 'a_tags',
                name: 'tags',
                type: BusinessAttributeType.string,
                isArray: true,
                estimatedMaxRows: 10,
                schemaConstraints: JsonSchemaConstraints(
                  minItems: 2,
                  maxItems: 10,
                  uniqueItems: true,
                  minLength: 2,
                ),
              ),
            ],
          ),
        ],
      );

      final bundle = SpecSuperDesignerExporter.toBundle(constrained);
      final schema = bundle.repositoriesJsonSchemas['produit']!;
      final seed = bundle.repositoriesSeedData['produit']!;
      final validation = JsonSchemaValidator.validate(seed, schema);
      expect(validation.isValid, isTrue, reason: validation.formatSummary());

      final props = ((schema['properties'] as Map)['produits'] as Map)['items']['properties'] as Map;
      expect((props['sku'] as Map)['pattern'], r'^[A-Z0-9-]+$');
      expect((props['prixHt'] as Map)['multipleOf'], 0.5);
      final tagsSchema = props['tags'] as Map;
      expect(tagsSchema['minItems'], 2);
      expect(tagsSchema['uniqueItems'], isTrue);
      expect((tagsSchema['items'] as Map)['minLength'], 2);

      // Conflit const / enum détecté par SpecCoherenceAnalyzer (COH-OBJ-011)
      final badConstProject = constrained.copyWith(
        businessObjects: [
          constrained.businessObjects.single.copyWith(
            attributes: [
              BusinessAttribute(
                id: 'a_etat',
                name: 'etat',
                type: BusinessAttributeType.enumeration,
                enumValues: const ['actif', 'archive'],
                schemaConstraints: JsonSchemaConstraints(
                  hasConst: true,
                  constValue: 'inconnu',
                ),
              ),
            ],
          ),
        ],
      );
      final issues = SpecCoherenceAnalyzer.analyze(badConstProject);
      expect(issues.any((i) => i.code == 'COH-OBJ-011'), isTrue);
    });

    test('SpecMarkdownHtmlBuilder charge les assets hors-ligne et génère HTML Mermaid/TOC/KaTeX/Print sécurisé', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final assets = await SpecMarkdownHtmlBuilder.loadAssets();
      expect(assets.hasOfflineScripts, isTrue);
      expect(assets.highlightJs, isNotEmpty);
      expect(assets.katexJs, isNotEmpty);
      expect(assets.katexCss, isNot(contains('@font-face')));

      final md = '''
# Titre <script>alert(1)</script>

> [!NOTE]
> Contenu avec formule \$E = mc^2\$

```mermaid
erDiagram
  COMMANDE ||--o{ LIGNE : contient
```
''';
      final html = SpecMarkdownHtmlBuilder.buildHtml(
        markdown: md,
        title: 'Doc <script>',
        assets: assets,
        darkMode: true,
        showToc: false,
      );

      expect(html, contains('data-theme="dark"'));
      expect(html, contains('ssf-toc-hidden'));
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('alert(1)</script>')));
      // Vérifie que la balise fermante </script> du markdown est bien échappée dans le JSON.
      expect(html, contains(r'<\/script>'));
      expect(html, contains('ssf-mermaid-card'));
      expect(html, contains('ssf-toc-list'));
      expect(html, contains('renderMathInElement'));
      expect(html, contains('@media print'));
    });

    test('SpecJsonSchemaHtmlBuilder génère la doc HTML5 interactive avec statut JsonSchemaValidator', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final assets = await SpecMarkdownHtmlBuilder.loadAssets();
      final project = buildSampleProject();
      final bundle = SpecSuperDesignerExporter.toBundle(project);

      final html = SpecJsonSchemaHtmlBuilder.buildHtml(
        bundle: bundle,
        title: 'Schémas <script>',
        assets: assets,
        darkMode: true,
      );
      expect(html, contains('data-theme="dark"'));
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('"isValid":true'));
      expect(html, contains('ssf-repos-data'));
      expect(html, contains('@media print'));

      // Cas invalide : seed ne respectant pas minItems/required.
      final invalidBundle = SuperDesignerExportBundle(
        yamlLightSchema: bundle.yamlLightSchema,
        repositoriesJsonSchemas: bundle.repositoriesJsonSchemas,
        repositoriesSeedData: {
          for (final k in bundle.repositoriesSeedData.keys)
            k: const <String, Object?>{},
        },
      );
      final invalidHtml = SpecJsonSchemaHtmlBuilder.buildHtml(
        bundle: invalidBundle,
        title: 'Schémas KO',
        assets: assets,
      );
      expect(invalidHtml, contains('"isValid":false'));
    });
  });
}
