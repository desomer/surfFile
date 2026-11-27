import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/models/business_object_spec.dart';
import 'package:super_spec_forge/models/business_rule_spec.dart';
import 'package:super_spec_forge/models/feature_object_sync_baseline.dart';
import 'package:super_spec_forge/models/json_schema_constraints.dart';
import 'package:super_spec_forge/models/qa/gherkin_feature_spec.dart';
import 'package:super_spec_forge/models/qa/qa_fixture_spec.dart';
import 'package:super_spec_forge/models/qa/qa_forge_spec.dart';
import 'package:super_spec_forge/models/qa/tdd_suite_spec.dart';
import 'package:super_spec_forge/models/spec_cahier_des_charges.dart';
import 'package:super_spec_forge/models/spec_coherence_issue.dart';
import 'package:super_spec_forge/models/spec_forge_project.dart';
import 'package:super_spec_forge/models/spec_forge_stage.dart';
import 'package:super_spec_forge/models/spec_initiative.dart';
import 'package:super_spec_forge/models/spec_lexicon.dart';
import 'package:super_spec_forge/models/spec_vision.dart';
import 'package:super_spec_forge/models/ux/ux_forge_spec.dart';
import 'package:super_spec_forge/models/ux/ux_screen_spec.dart';
import 'package:super_spec_forge/services/cross_feature_object_analyzer.dart';
import 'package:super_spec_forge/services/spec_coherence_analyzer.dart';

void main() {
  BusinessObjectSpec buildClientObject({String id = 'obj_client'}) =>
      BusinessObjectSpec(
        id: id,
        name: 'Client',
        technicalName: 'Client',
        description: 'Client locataire',
        attributes: <BusinessAttribute>[
          BusinessAttribute(
            id: 'attr_client_email',
            name: 'email',
            type: BusinessAttributeType.email,
            required: true,
          ),
          BusinessAttribute(
            id: 'attr_client_nom',
            name: 'nomComplet',
            type: BusinessAttributeType.string,
            required: true,
          ),
        ],
      );

  BusinessObjectSpec buildMvpVehiculeObject({
    String id = 'obj_vehicule',
    BusinessAttributeType immatriculationType = BusinessAttributeType.string,
    bool includePlafondKm = true,
    bool plafondKmRequired = false,
    List<BusinessAttribute> extraAttributes = const <BusinessAttribute>[],
    List<LifecycleState> extraStates = const <LifecycleState>[],
    List<LifecycleTransition> extraTransitions = const <LifecycleTransition>[],
  }) => BusinessObjectSpec(
    id: id,
    name: 'Véhicule',
    technicalName: 'Vehicule',
    description: 'Véhicule du parc locatif',
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_veh_immat',
        name: 'immatriculation',
        type: immatriculationType,
        required: true,
      ),
      if (includePlafondKm)
        BusinessAttribute(
          id: 'attr_veh_plafond',
          name: 'plafondKm',
          type: BusinessAttributeType.integer,
          required: plafondKmRequired,
          schemaConstraints: JsonSchemaConstraints(minimum: 100, maximum: 5000),
        ),
      BusinessAttribute(
        id: 'attr_veh_cat',
        name: 'categorie',
        type: BusinessAttributeType.enumeration,
        required: true,
        enumValues: const <String>['citadine', 'berline'],
      ),
      ...extraAttributes,
    ],
    lifecycleStates: <LifecycleState>[
      const LifecycleState(name: 'disponible', isInitial: true),
      const LifecycleState(name: 'loue'),
      ...extraStates,
    ],
    lifecycleTransitions: <LifecycleTransition>[
      const LifecycleTransition(
        id: 'tr_louer',
        fromState: 'disponible',
        toState: 'loue',
        trigger: 'Remise des clés',
      ),
      ...extraTransitions,
    ],
  );

  SpecFeatureSpec buildValidatedMvpFeature() => SpecFeatureSpec(
    id: 'feat_mvp',
    code: 'FEAT-01',
    name: 'Socle Location MVP',
    status: SpecPortfolioStatus.validated,
    vision: SpecVision(
      ideaSummary: 'Gestion du parc locatif MVP',
      objectives: const <String>['Fiabiliser la flotte'],
      personas: <SpecPersona>[
        SpecPersona(id: 'p_agent', name: 'Agent agence', role: 'Gestionnaire'),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const <SpecModule>[SpecModule(id: 'mod_parc', name: 'Parc')],
      functionalRequirements: <FunctionalRequirement>[
        FunctionalRequirement(
          id: 'req_mvp_1',
          code: 'EXF-001',
          title: 'Enregistrer un véhicule',
          moduleId: 'mod_parc',
          actorIds: const <String>['p_agent'],
        ),
      ],
    ),
    businessObjects: <BusinessObjectSpec>[
      buildClientObject(),
      buildMvpVehiculeObject(),
    ],
    businessRules: <BusinessRuleSpec>[
      BusinessRuleSpec(
        id: 'rg_plafond_km',
        code: 'RG-001',
        title: 'Contrôle du plafond kilométrique',
        category: BusinessRuleCategory.validation,
        targetObjectIds: const <String>['obj_vehicule'],
        targetAttributes: const <String>['Vehicule.plafondKm'],
        condition: 'plafondKm > 0',
        effect: 'Autorise la mise en location',
      ),
    ],
    uxSpec: UxForgeSpec(
      screens: <UxScreenSpec>[
        UxScreenSpec(
          id: 'scr_parc',
          code: 'SCR-001',
          name: 'Fiche Véhicule',
          primaryObjectId: 'obj_vehicule',
          zones: <UxScreenZoneSpec>[
            UxScreenZoneSpec(
              zone: UxLayoutZoneName.center,
              slots: <UxZoneWidgetSlot>[
                UxZoneWidgetSlot(
                  id: 'slot_veh_detail',
                  title: 'Caractéristiques véhicule',
                  kind: UxWidgetKind.detailCard,
                  businessObjectId: 'obj_vehicule',
                  attributeNames: const <String>[
                    'immatriculation',
                    'plafondKm',
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    qaSpec: QaForgeSpec(
      fixtures: <QaFixtureSpec>[
        QaFixtureSpec(
          id: 'fix_veh_nominal',
          code: 'FIX-001',
          name: 'Véhicule citadine nominal',
          kind: QaFixtureKind.nominal,
          businessObjectId: 'obj_vehicule',
          businessRuleIds: const <String>['RG-001'],
          payload: const <String, Object?>{
            'immatriculation': 'AA-123-BB',
            'plafondKm': 1200,
            'categorie': 'citadine',
          },
          expectedValid: true,
        ),
      ],
      tddSuites: <TddTestSuiteSpec>[
        TddTestSuiteSpec(
          id: 'tdd_vehicule',
          code: 'TDD-001',
          name: 'Validation Véhicule',
          targetObjectId: 'obj_vehicule',
          cases: <TddTestCaseSpec>[
            TddTestCaseSpec(
              id: 'tc_plafond',
              code: 'TC-001',
              order: 1,
              title: 'Vérifie plafondKm nominal',
              fixtureId: 'FIX-001',
              arrange: 'Vehicule avec plafondKm = 1200',
              act: 'validerPlafond()',
              assertExpected: 'valide == true',
              businessRuleIds: const <String>['RG-001'],
            ),
          ],
        ),
      ],
    ),
  );

  SpecFeatureSpec buildLot2BaseFeature({
    required List<BusinessObjectSpec> businessObjects,
    SpecPortfolioStatus status = SpecPortfolioStatus.inProgress,
    Map<String, FeatureObjectSyncBaseline> objectSyncBaselines =
        const <String, FeatureObjectSyncBaseline>{},
    List<BusinessRuleSpec> businessRules = const <BusinessRuleSpec>[],
    UxForgeSpec? uxSpec,
  }) => SpecFeatureSpec(
    id: 'feat_lot2',
    code: 'FEAT-02',
    name: 'Télématique & Maintenance Lot 2',
    status: status,
    vision: SpecVision(
      ideaSummary: 'Suivi GPS et maintenance préventive',
      objectives: const <String>['Réduire les pannes'],
      personas: <SpecPersona>[
        SpecPersona(
          id: 'p_tech',
          name: 'Responsable flotte',
          role: 'Superviseur',
        ),
      ],
    ),
    cahierDesCharges: SpecCahierDesCharges(
      modules: const <SpecModule>[
        SpecModule(id: 'mod_maint', name: 'Maintenance'),
      ],
      functionalRequirements: <FunctionalRequirement>[
        FunctionalRequirement(
          id: 'req_lot2_1',
          code: 'EXF-010',
          title: 'Suivre les balises GPS',
          moduleId: 'mod_maint',
          actorIds: const <String>['p_tech'],
        ),
      ],
    ),
    businessObjects: businessObjects,
    objectSyncBaselines: objectSyncBaselines,
    businessRules: businessRules.isNotEmpty
        ? businessRules
        : <BusinessRuleSpec>[
            BusinessRuleSpec(
              id: 'rg_lot2_1',
              code: 'RG-010',
              title: 'Alerte maintenance',
              targetObjectIds: <String>[businessObjects.first.id],
              condition: 'true',
              effect: 'Notification envoyée',
            ),
          ],
    uxSpec: uxSpec,
  );

  SpecForgeProject buildProjectWithFeatures({
    required List<SpecFeatureSpec> features,
    required String activeFeatureId,
  }) {
    final now = DateTime.utc(2026, 11, 27, 20);
    return SpecForgeProject(
      id: 'proj_fleet',
      name: 'Fleet Manager',
      initialIdea: 'Gestion de flotte automobile multi-lots',
      createdAt: now,
      updatedAt: now,
      lexicon: SpecLexicon(
        terms: <LexiconTerm>[
          LexiconTerm(
            id: 'lex_veh',
            term: 'Véhicule',
            definition: 'Automobile destinée à la location courte durée.',
          ),
        ],
      ),
      initiatives: <SpecInitiative>[
        SpecInitiative(
          id: 'init_1',
          code: 'INIT-01',
          name: 'Plateforme Flotte',
          features: features,
        ),
      ],
      activeFeatureId: activeFeatureId,
    );
  }

  group(
    'CrossFeatureObjectAnalyzer & gouvernance additive_warn_on_validated',
    () {
      test(
        'projet mono-feature : sharedObjectCount == 0 et aucun COH-FEAT-*',
        () {
          final mvp = buildValidatedMvpFeature();
          final project = buildProjectWithFeatures(
            features: <SpecFeatureSpec>[mvp],
            activeFeatureId: mvp.id,
          );

          final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
          expect(report.featureId, mvp.id);
          expect(report.sharedObjectCount, 0);
          expect(report.localOnlyObjectCount, 2);
          expect(report.warningObjectCount, 0);
          expect(report.warnings, isEmpty);

          final issues = SpecCoherenceAnalyzer.analyze(project);
          expect(issues.where((i) => i.code.startsWith('COH-FEAT-')), isEmpty);
        },
      );

      test('objet Client identique et extension additive sur Vehicule (gpsTrackerId + état en_maintenance) : zéro warning', () {
        final feat1 = buildValidatedMvpFeature();
        final feat2 = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(id: 'obj_client'),
            buildMvpVehiculeObject(
              extraAttributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_gps_tracker',
                  name: 'gpsTrackerId',
                  type: BusinessAttributeType.string,
                  required: false,
                  description: 'Identifiant du boîtier télématique optionnel',
                ),
              ],
              extraStates: const <LifecycleState>[
                LifecycleState(name: 'en_maintenance'),
              ],
              extraTransitions: const <LifecycleTransition>[
                LifecycleTransition(
                  id: 'tr_maint',
                  fromState: 'disponible',
                  toState: 'en_maintenance',
                  trigger: 'Entrée atelier',
                ),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_intervention',
              name: 'Intervention',
              technicalName: 'Intervention',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_inter_id',
                  name: 'codeIntervention',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2],
          activeFeatureId: feat2.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        expect(report.sharedObjectCount, 2);
        expect(report.localOnlyObjectCount, 1);
        expect(report.warningObjectCount, 0);
        expect(report.warnings, isEmpty);

        final clientReport = report.byObjectId['obj_client']!;
        expect(clientReport.isSharedAcrossFeatures, isTrue);
        expect(clientReport.sharedWithValidatedFeature, isTrue);
        expect(clientReport.hasBreakingValidatedWarning, isFalse);
        expect(clientReport.sharedFeaturesSummary, 'FEAT-01');
        expect(
          clientReport.siblingLinks.single.divergence,
          CrossFeatureDivergenceKind.identical,
        );

        final vehiculeReport = report.byObjectId['obj_vehicule']!;
        expect(vehiculeReport.isSharedAcrossFeatures, isTrue);
        expect(vehiculeReport.sharedWithValidatedFeature, isTrue);
        expect(vehiculeReport.hasBreakingValidatedWarning, isFalse);
        expect(vehiculeReport.totalDownstreamImpactCount, 0);
        final vehLink = vehiculeReport.siblingLinks.single;
        expect(vehLink.divergence, CrossFeatureDivergenceKind.additive);
        expect(
          vehLink.differenceSummaries.join(' | '),
          contains('gpsTrackerId'),
        );
        expect(
          vehLink.differenceSummaries.join(' | '),
          contains('en_maintenance'),
        );

        final issues = SpecCoherenceAnalyzer.analyze(project);
        expect(issues.where((i) => i.code.startsWith('COH-FEAT-')), isEmpty);
      });

      test('attribut optionnel non importé depuis une feature sœur non validée : behindSibling sans fausse alerte cassante', () {
        final feat1InProgress = buildValidatedMvpFeature().copyWith(
          status: SpecPortfolioStatus.inProgress,
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(
              extraAttributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_note_interne',
                  name: 'noteInterne',
                  type: BusinessAttributeType.string,
                  required: false,
                ),
              ],
            ),
          ],
        );
        final feat2 = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1InProgress, feat2],
          activeFeatureId: feat2.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        final vehLink = report.byObjectId['obj_vehicule']!.siblingLinks.single;
        expect(vehLink.divergence, CrossFeatureDivergenceKind.behindSibling);
        expect(vehLink.hasValidatedWarning, isFalse);
        expect(report.warningObjectCount, 0);

        final issues = SpecCoherenceAnalyzer.analyze(project);
        expect(issues.where((i) => i.code.startsWith('COH-FEAT-')), isEmpty);
      });

      test('rupture de type (immatriculation string -> integer) face à FEAT-01 validée : breaking + impacts RG/UX/QA + COH-FEAT-001/002', () {
        final feat1 = buildValidatedMvpFeature();
        final feat2 = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(
              immatriculationType: BusinessAttributeType.integer,
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2],
          activeFeatureId: feat2.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        expect(report.warningObjectCount, 1);
        final vehReport = report.byObjectId['obj_vehicule']!;
        expect(vehReport.hasBreakingValidatedWarning, isTrue);

        final link = vehReport.siblingLinks.single;
        expect(link.divergence, CrossFeatureDivergenceKind.breaking);
        expect(link.isSiblingValidated, isTrue);
        expect(link.hasValidatedWarning, isTrue);
        expect(
          link.differenceSummaries.any(
            (s) => s.contains('immatriculation') && s.contains('integer'),
          ),
          isTrue,
        );
        expect(
          link.downstreamImpacts.map((i) => i.area),
          containsAll(<CrossFeatureDownstreamArea>[
            CrossFeatureDownstreamArea.ux,
            CrossFeatureDownstreamArea.qa,
          ]),
        );

        final issues = SpecCoherenceAnalyzer.analyze(project);
        final coh1 = issues.where((i) => i.code == 'COH-FEAT-001').toList();
        final coh2 = issues.where((i) => i.code == 'COH-FEAT-002').toList();
        expect(coh1, hasLength(1));
        expect(coh1.single.targetRef, 'obj_vehicule');
        expect(coh1.single.stage, SpecForgeStage.businessObjects);
        expect(coh1.single.severity, CoherenceSeverity.warning);
        expect(coh1.single.title, contains('FEAT-01'));
        expect(coh1.single.description, contains('immatriculation'));
        expect(coh1.single.suggestion, contains('Importer / Synchroniser'));

        expect(coh2, hasLength(1));
        expect(coh2.single.targetRef, 'obj_vehicule');
        expect(coh2.single.description, contains('SCR-001'));
        expect(coh2.single.description, contains('FIX-001'));
      });

      test('suppression de plafondKm utilisé par RG-001, SCR-001 et FIX-001/TDD-001 dans FEAT-01 validée : breaking + impacts RG/UX/QA + COH-FEAT-001 & COH-FEAT-002', () {
        final feat1 = buildValidatedMvpFeature();
        final feat2 = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(includePlafondKm: false),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2],
          activeFeatureId: feat2.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        expect(report.warningObjectCount, 1);
        final vehReport = report.byObjectId['obj_vehicule']!;
        expect(vehReport.hasBreakingValidatedWarning, isTrue);
        expect(vehReport.totalDownstreamImpactCount, greaterThanOrEqualTo(3));

        final link = vehReport.siblingLinks.single;
        expect(link.divergence, CrossFeatureDivergenceKind.breaking);
        final areas = link.downstreamImpacts.map((i) => i.area).toSet();
        expect(
          areas,
          containsAll(<CrossFeatureDownstreamArea>[
            CrossFeatureDownstreamArea.businessRule,
            CrossFeatureDownstreamArea.ux,
            CrossFeatureDownstreamArea.qa,
          ]),
        );
        final refs = link.downstreamImpacts.map((i) => i.artifactRef).toSet();
        expect(
          refs,
          containsAll(<String>['RG-001', 'SCR-001', 'FIX-001', 'TDD-001']),
        );

        final issues = SpecCoherenceAnalyzer.analyze(project);
        final coh1 = issues.firstWhere((i) => i.code == 'COH-FEAT-001');
        final coh2 = issues.firstWhere((i) => i.code == 'COH-FEAT-002');
        expect(coh1.targetRef, 'obj_vehicule');
        expect(coh1.description, contains('plafondKm'));
        expect(coh2.targetRef, 'obj_vehicule');
        expect(coh2.title, contains('RG-001'));
        expect(coh2.title, contains('SCR-001'));
        expect(coh2.title, contains('FIX-001'));
      });

      test('ajout d’un attribut required: true sans defaultValue face à FEAT-01 validée : breaking + impact sur fixture nominale FIX-001 + COH-FEAT-001 & COH-FEAT-002', () {
        final feat1 = buildValidatedMvpFeature();
        final feat2 = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(
              extraAttributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_vin',
                  name: 'numeroVin',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2],
          activeFeatureId: feat2.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        final vehReport = report.byObjectId['obj_vehicule']!;
        expect(vehReport.hasBreakingValidatedWarning, isTrue);

        final link = vehReport.siblingLinks.single;
        expect(link.divergence, CrossFeatureDivergenceKind.breaking);
        expect(
          link.differenceSummaries.any((s) => s.contains('numeroVin')),
          isTrue,
        );
        expect(
          link.downstreamImpacts.any(
            (i) =>
                i.area == CrossFeatureDownstreamArea.qa &&
                i.artifactRef == 'FIX-001' &&
                i.attributeOrStateName == 'numeroVin',
          ),
          isTrue,
        );

        final issues = SpecCoherenceAnalyzer.analyze(project);
        expect(issues.any((i) => i.code == 'COH-FEAT-001'), isTrue);
        expect(issues.any((i) => i.code == 'COH-FEAT-002'), isTrue);
      });

      test('selfValidatedImpacts détecte la casse locale vis-à-vis de la FeatureObjectSyncBaseline', () {
        final feat1 = buildValidatedMvpFeature();
        final baseVehicule = buildMvpVehiculeObject();
        final feat2 = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(includePlafondKm: false),
          ],
          objectSyncBaselines: <String, FeatureObjectSyncBaseline>{
            'obj_vehicule': FeatureObjectSyncBaseline(
              objectId: 'obj_vehicule',
              sourceKind: ObjectSyncSourceKind.feature,
              sourceFeatureId: feat1.id,
              sourceFeatureCode: feat1.code,
              sourceFeatureName: feat1.name,
              sourceEntryId: 'obj_vehicule',
              syncedAt: DateTime.utc(2026, 11, 27, 19),
              baseObject: baseVehicule,
            ),
          },
          businessRules: <BusinessRuleSpec>[
            BusinessRuleSpec(
              id: 'rg_local_km',
              code: 'RG-020',
              title: 'Règle locale kilométrage',
              targetObjectIds: const <String>['obj_vehicule'],
              targetAttributes: const <String>['plafondKm'],
              condition: 'plafondKm <= 3000',
              effect: 'OK',
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2],
          activeFeatureId: feat2.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        final vehReport = report.byObjectId['obj_vehicule']!;
        expect(vehReport.selfValidatedImpacts, isNotEmpty);
        expect(
          vehReport.selfValidatedImpacts.any(
            (i) =>
                i.artifactRef == 'RG-020' &&
                i.attributeOrStateName == 'plafondKm',
          ),
          isTrue,
        );
      });

      test('analyzePortfolio calcule uniqueCanonicalObjectCount, sharedCanonicalObjectCount, featuresWithWarningsCount et ignore les features archivées', () {
        final feat1 = buildValidatedMvpFeature(); // Client + Vehicule
        final feat2 = buildLot2BaseFeature(
          // Client (identique) + Vehicule (cassant: sans plafondKm) + Intervention (local)
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(id: 'obj_client_lot2'),
            buildMvpVehiculeObject(includePlafondKm: false),
            BusinessObjectSpec(
              id: 'obj_intervention',
              name: 'Intervention',
              technicalName: 'Intervention',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_inter_code',
                  name: 'code',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
              ],
            ),
          ],
        );
        final feat3Archived = SpecFeatureSpec(
          id: 'feat_archived',
          code: 'FEAT-03',
          name: 'Ancien module abandonné',
          status: SpecPortfolioStatus.archived,
          businessObjects: <BusinessObjectSpec>[
            // Même cassant, FEAT-03 est archivée et doit être ignorée partout !
            buildClientObject(id: 'obj_client_arch').copyWith(
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_client_email',
                  name: 'email',
                  type: BusinessAttributeType.integer,
                  required: true,
                ),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_archive_seul',
              name: 'Objet Archivé',
              technicalName: 'ObjetArchive',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_arch_1',
                  name: 'code',
                  type: BusinessAttributeType.string,
                ),
              ],
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2, feat3Archived],
          activeFeatureId: feat1.id,
        );

        final summary = CrossFeatureObjectAnalyzer.analyzePortfolio(project);
        // Objets canoniques hors FEAT-03 archivée : Client, Vehicule, Intervention => 3
        expect(summary.uniqueCanonicalObjectCount, 3);
        // Objets partagés par >= 2 features actives : Client, Vehicule => 2
        expect(summary.sharedCanonicalObjectCount, 2);
        // Seule FEAT-02 est en rupture contre FEAT-01 validée (FEAT-01 n'est pas cassante envers FEAT-02 non validée, et FEAT-03 est ignorée) => 1
        expect(summary.featuresWithWarningsCount, 1);

        // FEAT-03 n'apparaît dans aucun siblingLinks de FEAT-01 ni FEAT-02
        final feat1ClientLinks = summary
            .byFeatureId[feat1.id]!
            .byObjectId['obj_client']!
            .siblingLinks;
        expect(
          feat1ClientLinks.map((l) => l.featureCode).toList(),
          equals(<String>['FEAT-02']),
        );

        final feat3Report = summary.byFeatureId[feat3Archived.id]!;
        expect(feat3Report.sharedObjectCount, 0);
        expect(feat3Report.warningObjectCount, 0);

        // Lorsque la feature active est elle-même archivée, SpecCoherenceAnalyzer n'émet aucun COH-FEAT-*
        final archivedActiveProject = project.selectFeature(feat3Archived.id);
        final archivedIssues = SpecCoherenceAnalyzer.analyze(
          archivedActiveProject,
        );
        expect(
          archivedIssues.where((i) => i.code.startsWith('COH-FEAT-')),
          isEmpty,
        );
      });

      test('durcissement de contraintes, retrait de valeur enum, cardinalité modifiée et impact scénario Gherkin SCN-001', () {
        final feat1WithGherkin = buildValidatedMvpFeature().copyWith(
          qaSpec: buildValidatedMvpFeature().qaSpec.copyWith(
            features: <GherkinFeatureSpec>[
              GherkinFeatureSpec(
                id: 'ghk_veh',
                code: 'GHK-001',
                title: 'Contrôle Véhicule',
                scenarios: <GherkinScenarioSpec>[
                  GherkinScenarioSpec(
                    id: 'scn_plafond',
                    code: 'SCN-001',
                    title: 'Vérifier le plafond kilométrique du Véhicule',
                    isOutline: true,
                    businessRuleIds: const <String>['RG-001'],
                    steps: <GherkinStep>[
                      GherkinStep(
                        id: 'st_1',
                        keyword: GherkinStepKeyword.given,
                        text: 'un véhicule avec plafond <plafondKm>',
                      ),
                      GherkinStep(
                        id: 'st_2',
                        keyword: GherkinStepKeyword.then,
                        text: 'le dossier est accepté',
                      ),
                    ],
                    examples: GherkinExamplesTable(
                      headers: const <String>['plafondKm'],
                      rows: const <List<String>>[
                        <String>['1200'],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        final feat2Tightened = buildLot2BaseFeature(
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            BusinessObjectSpec(
              id: 'obj_vehicule',
              name: 'Véhicule',
              technicalName: 'Vehicule',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_veh_immat',
                  name: 'immatriculation',
                  type: BusinessAttributeType.string,
                  required: true,
                  isArray: true,
                ),
                BusinessAttribute(
                  id: 'attr_veh_plafond',
                  name: 'plafondKm',
                  type: BusinessAttributeType.integer,
                  required: false,
                  schemaConstraints: JsonSchemaConstraints(
                    minimum: 500,
                    maximum: 2000,
                  ),
                ),
                BusinessAttribute(
                  id: 'attr_veh_cat',
                  name: 'categorie',
                  type: BusinessAttributeType.enumeration,
                  required: true,
                  enumValues: const <String>['citadine'],
                ),
              ],
              lifecycleStates: const <LifecycleState>[
                LifecycleState(name: 'disponible', isInitial: true),
                LifecycleState(name: 'loue'),
              ],
              lifecycleTransitions: const <LifecycleTransition>[
                LifecycleTransition(
                  id: 'tr_louer',
                  fromState: 'disponible',
                  toState: 'loue',
                ),
              ],
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1WithGherkin, feat2Tightened],
          activeFeatureId: feat2Tightened.id,
        );

        final report = CrossFeatureObjectAnalyzer.analyzeFeature(project);
        final link = report.byObjectId['obj_vehicule']!.siblingLinks.single;
        expect(link.divergence, CrossFeatureDivergenceKind.breaking);
        final allDiffs = link.differenceSummaries.join(' | ');
        expect(allDiffs, contains('cardinalité'));
        expect(allDiffs, contains('minimum'));
        expect(allDiffs, contains('maximum'));
        expect(allDiffs, contains('berline'));
        expect(
          link.downstreamImpacts.any((i) => i.artifactRef == 'SCN-001'),
          isTrue,
        );
      });

      test('deux features toutes deux Validées avec extension purement additive : featuresWithWarningsCount == 0', () {
        final feat1 = buildValidatedMvpFeature();
        final feat2ValidatedAdditive = buildLot2BaseFeature(
          status: SpecPortfolioStatus.validated,
          businessObjects: <BusinessObjectSpec>[
            buildClientObject(),
            buildMvpVehiculeObject(
              extraAttributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_gps',
                  name: 'gpsTrackerId',
                  type: BusinessAttributeType.string,
                  required: false,
                ),
              ],
              extraStates: const <LifecycleState>[
                LifecycleState(name: 'en_maintenance'),
              ],
            ),
          ],
        );

        final project = buildProjectWithFeatures(
          features: <SpecFeatureSpec>[feat1, feat2ValidatedAdditive],
          activeFeatureId: feat2ValidatedAdditive.id,
        );

        final summary = CrossFeatureObjectAnalyzer.analyzePortfolio(project);
        expect(summary.featuresWithWarningsCount, 0);
        expect(
          summary
              .byFeatureId[feat2ValidatedAdditive.id]!
              .byObjectId['obj_vehicule']!
              .siblingLinks
              .single
              .divergence,
          CrossFeatureDivergenceKind.additive,
        );
        expect(
          summary
              .byFeatureId[feat1.id]!
              .byObjectId['obj_vehicule']!
              .siblingLinks
              .single
              .divergence,
          CrossFeatureDivergenceKind.behindSibling,
        );
      });
    },
  );
}
