import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

    test('SpecProjectStore sauvegarde en multi-fichiers, liste via manifest.json, recharge, met à jour incrémentalement et supprime', () async {
      final tempDir = await Directory.systemTemp.createTemp('spec_forge_store_');
      try {
        final store = SpecProjectStore(tempDir);
        final sep = Platform.pathSeparator;
        final baseProject = buildSampleProject();

        final textAttachment = VibeChatAttachment.text(
          name: 'cahier.md',
          content: '# Note métier\nContenu détaillé en UTF-8.',
        );
        final binaryAttachment = VibeChatAttachment.image(
          name: 'schema.png',
          bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]),
          mimeType: 'image/png',
        );
        final project = baseProject
            .withStageState(
              SpecStageState(
                stage: SpecForgeStage.lexicon,
                status: SpecStageStatus.inProgress,
                messages: [
                  SpecChatMessage(
                    id: 'm1',
                    isUser: true,
                    text: 'Analyse ces deux documents',
                    attachments: [textAttachment, binaryAttachment],
                  ),
                ],
              ),
              updatedAt: baseProject.updatedAt,
            )
            .copyWith(
              globalChatMessages: [
                SpecChatMessage(
                  id: 'gm1',
                  isUser: true,
                  text: 'Question globale',
                  attachments: [textAttachment],
                ),
              ],
              updatedAt: baseProject.updatedAt,
            );

        await store.saveProject(project);

        final projPath = '${tempDir.path}${sep}projects$sep${project.id}';
        expect(await File('$projPath${sep}project.json').exists(), isFalse);
        expect(await File('$projPath${sep}manifest.json').exists(), isTrue);
        expect(
          await File('$projPath${sep}spec${sep}lexicon.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}spec${sep}vision.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}spec${sep}cahier_des_charges.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}spec${sep}business_objects.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}spec${sep}business_rules.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}spec${sep}model_preferences.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}spec${sep}coherence_issues.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}chats${sep}stage_lexicon.json').exists(),
          isTrue,
        );
        expect(
          await File('$projPath${sep}chats${sep}global_chat.json').exists(),
          isTrue,
        );

        // Vérifie l'externalisation des pièces jointes dans attachments/.
        final attachmentsDir = Directory('$projPath${sep}attachments');
        expect(await attachmentsDir.exists(), isTrue);
        final attachmentFiles = await attachmentsDir.list().toList();
        expect(attachmentFiles.length, 2);
        final stageChatRaw = await File(
          '$projPath${sep}chats${sep}stage_lexicon.json',
        ).readAsString();
        expect(stageChatRaw, contains('"storageFile"'));
        expect(stageChatRaw, isNot(contains('"bytesBase64"')));
        expect(stageChatRaw, isNot(contains('Contenu détaillé en UTF-8.')));

        // listProjects() fonctionne uniquement via manifest.json.
        final list = await store.listProjects();
        expect(list.length, 1);
        expect(list.single.name, 'B2B Orders');
        expect(list.single.objectCount, 1);
        expect(list.single.ruleCount, 1);

        final loaded = await store.loadProject(project.id);
        expect(loaded, equals(project));
        expect(await store.getLastActiveProjectId(), project.id);

        // Sauvegarde incrémentale : seul lexique + manifeste doivent être réécrits.
        final pastTime = DateTime(2020, 1, 1);
        final lexiconFile = File('$projPath${sep}spec${sep}lexicon.json');
        final visionFile = File('$projPath${sep}spec${sep}vision.json');
        final objectsFile = File(
          '$projPath${sep}spec${sep}business_objects.json',
        );
        final globalChatFile = File('$projPath${sep}chats${sep}global_chat.json');
        lexiconFile.setLastModifiedSync(pastTime);
        visionFile.setLastModifiedSync(pastTime);
        objectsFile.setLastModifiedSync(pastTime);
        globalChatFile.setLastModifiedSync(pastTime);

        final updatedLexicon = project.copyWith(
          lexicon: project.lexicon.copyWith(
            terms: [
              ...project.lexicon.terms,
              LexiconTerm(
                id: 't_client',
                term: 'Acheteur',
                definition: 'Collaborateur autorisé à passer commande.',
              ),
            ],
          ),
        );
        await store.saveProject(updatedLexicon);

        expect(lexiconFile.lastModifiedSync().isAfter(pastTime), isTrue);
        expect(visionFile.lastModifiedSync(), equals(pastTime));
        expect(objectsFile.lastModifiedSync(), equals(pastTime));
        expect(globalChatFile.lastModifiedSync(), equals(pastTime));

        // Nettoyage des pièces jointes orphelines après suppression du message binaire.
        final withoutBinary = updatedLexicon.withStageState(
          SpecStageState(
            stage: SpecForgeStage.lexicon,
            status: SpecStageStatus.inProgress,
            messages: [
              SpecChatMessage(
                id: 'm1',
                isUser: true,
                text: 'Analyse ce document',
                attachments: [textAttachment],
              ),
            ],
          ),
        );
        await store.saveProject(withoutBinary);
        final remainingAttachments = await attachmentsDir.list().toList();
        expect(remainingAttachments.length, 1);

        // listProjects() reste opérationnel même avec un dossier ne contenant que manifest.json.
        final manifestOnlyDir = Directory(
          '${tempDir.path}${sep}projects${sep}proj_manifest_only',
        );
        await manifestOnlyDir.create(recursive: true);
        await File('${manifestOnlyDir.path}${sep}manifest.json').writeAsString(
          jsonEncode({
            'format': SpecProjectStore.manifestFormat,
            'version': SpecProjectStore.storageVersion,
            'id': 'proj_manifest_only',
            'name': 'Manifeste seul',
            'initialIdea': 'Idée test',
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-02T00:00:00.000Z',
            'currentStage': 'vision',
            'objectCount': 4,
            'ruleCount': 7,
          }),
        );
        final twoProjects = await store.listProjects();
        expect(twoProjects.length, 2);
        final manifestOnlySummary = twoProjects.firstWhere(
          (p) => p.id == 'proj_manifest_only',
        );
        expect(manifestOnlySummary.objectCount, 4);
        expect(manifestOnlySummary.ruleCount, 7);

        await store.deleteProject(project.id);
        await store.deleteProject('proj_manifest_only');
        expect(await store.listProjects(), isEmpty);
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

    test('SpecSuperDesignerExporter applique schemaStrictness.strict et localeProfile US/USD', () {
      final base = buildSampleProject();
      final strictProject = base.copyWith(
        businessObjectModelPreferences: const BusinessObjectModelPreferences(
          schemaStrictness: JsonSchemaStrictness.strict,
          localeProfile: ModelLocaleProfile.usUsd,
        ),
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_account',
            name: 'Account',
            technicalName: 'Account',
            attributes: [
              BusinessAttribute(
                id: 'a_email',
                name: 'email',
                type: BusinessAttributeType.email,
                required: true,
              ),
              BusinessAttribute(
                id: 'a_profile',
                name: 'profile',
                type: BusinessAttributeType.object,
                children: [
                  BusinessAttribute(
                    id: 'a_site',
                    name: 'website',
                    type: BusinessAttributeType.url,
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final bundle = SpecSuperDesignerExporter.toBundle(strictProject);
      final schema = bundle.repositoriesJsonSchemas['account']!;
      final seed = bundle.repositoriesSeedData['account']!;
      expect(schema['additionalProperties'], isFalse);

      final itemSchema =
          ((schema['properties'] as Map)['accounts'] as Map)['items'] as Map;
      expect(itemSchema['additionalProperties'], isFalse);
      final profileSchema = (itemSchema['properties'] as Map)['profile'] as Map;
      expect(profileSchema['additionalProperties'], isFalse);

      final seedRow = ((seed['accounts'] as List).single as Map);
      expect(seedRow['email'], 'contact@example.com');
      expect((seedRow['profile'] as Map)['website'], 'https://example.com');
      expect(JsonSchemaValidator.validate(seed, schema).isValid, isTrue);
    });
  });
}
