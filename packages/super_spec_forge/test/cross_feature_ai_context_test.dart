import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  SpecForgeProject buildFleetPortfolioProject() {
    final vehiculeFeat1 = BusinessObjectSpec(
      id: 'obj_vehicule',
      name: 'Véhicule',
      technicalName: 'Vehicule',
      description: 'Véhicule immatriculé du parc entreprise',
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_immat',
          name: 'immatriculation',
          type: BusinessAttributeType.string,
          required: true,
          description: 'Plaque SIV',
        ),
        BusinessAttribute(
          id: 'attr_km',
          name: 'kilometrage',
          type: BusinessAttributeType.integer,
          description: 'Compteur en km',
        ),
        BusinessAttribute(
          id: 'attr_motorisation',
          name: 'motorisation',
          type: BusinessAttributeType.enumeration,
          required: true,
          enumValues: const <String>['thermique', 'hybride', 'electrique'],
        ),
        BusinessAttribute(
          id: 'attr_depot',
          name: 'depotId',
          type: BusinessAttributeType.reference,
          referenceObjectId: 'obj_depot',
        ),
        BusinessAttribute(
          id: 'attr_assurance',
          name: 'contratAssurance',
          type: BusinessAttributeType.object,
          children: <BusinessAttribute>[
            BusinessAttribute(
              id: 'attr_assureur',
              name: 'assureur',
              type: BusinessAttributeType.string,
              required: true,
            ),
          ],
        ),
      ],
      lifecycleStates: const <LifecycleState>[
        LifecycleState(
          name: 'disponible',
          label: 'Disponible',
          isInitial: true,
        ),
        LifecycleState(name: 'reforme', label: 'Réformé', isTerminal: true),
      ],
    );

    final conducteurFeat1 = BusinessObjectSpec(
      id: 'obj_conducteur',
      name: 'Conducteur',
      technicalName: 'Conducteur',
      attributes: <BusinessAttribute>[
        BusinessAttribute(
          id: 'attr_matricule',
          name: 'matricule',
          type: BusinessAttributeType.string,
          required: true,
        ),
      ],
    );

    final feat1Validated =
        SpecFeatureSpec.create(
          id: 'feat_parc',
          code: 'FEAT-01',
          name: 'Parc véhicules',
          status: SpecPortfolioStatus.validated,
        ).copyWith(
          businessObjects: <BusinessObjectSpec>[vehiculeFeat1, conducteurFeat1],
          businessRules: <BusinessRuleSpec>[
            BusinessRuleSpec(
              id: 'rule_rg_001',
              code: 'RG-001',
              title: 'Contrôle périodique 15 000 km',
              category: BusinessRuleCategory.trigger,
              targetObjectIds: const <String>['obj_vehicule'],
              targetAttributes: const <String>['Vehicule.kilometrage'],
            ),
            BusinessRuleSpec(
              id: 'rule_rg_002',
              code: 'RG-002',
              title: 'Permis valide obligatoire',
              targetObjectIds: const <String>['obj_conducteur'],
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
                        id: 'slot_veh',
                        title: 'Détail véhicule',
                        businessObjectId: 'obj_vehicule',
                        attributeNames: const <String>[
                          'immatriculation',
                          'kilometrage',
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
                id: 'fix_veh_ok',
                code: 'FIX-001',
                name: 'Véhicule électrique neuf',
                businessObjectId: 'obj_vehicule',
                payload: const <String, Object?>{
                  'immatriculation': 'AA-123-BB',
                  'kilometrage': 120,
                },
              ),
            ],
          ),
        );

    // FEAT-02 est la feature active : contient déjà Conducteur + un objet propre Reservation.
    final feat2Active =
        SpecFeatureSpec.create(
          id: 'feat_resa',
          code: 'FEAT-02',
          name: 'Réservation collaborateur',
        ).copyWith(
          currentStage: SpecForgeStage.businessObjects,
          businessObjects: <BusinessObjectSpec>[
            conducteurFeat1,
            BusinessObjectSpec(
              id: 'obj_reservation',
              name: 'Réservation',
              technicalName: 'Reservation',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_debut',
                  name: 'dateDebut',
                  type: BusinessAttributeType.datetime,
                  required: true,
                ),
              ],
            ),
          ],
        );

    // FEAT-03 est en cours : étend Vehicule avec autonomieKm + sous-attribut franchise et ajoute Sinistre.
    final feat3InProgress =
        SpecFeatureSpec.create(
          id: 'feat_sinistres',
          code: 'FEAT-03',
          name: 'Gestion des sinistres',
        ).copyWith(
          businessObjects: <BusinessObjectSpec>[
            BusinessObjectSpec(
              id: 'obj_vehicule',
              name: 'Véhicule',
              technicalName: 'Vehicule',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_immat',
                  name: 'immatriculation',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
                BusinessAttribute(
                  id: 'attr_autonomie',
                  name: 'autonomieKm',
                  type: BusinessAttributeType.integer,
                ),
                BusinessAttribute(
                  id: 'attr_assurance',
                  name: 'contratAssurance',
                  type: BusinessAttributeType.object,
                  children: <BusinessAttribute>[
                    BusinessAttribute(
                      id: 'attr_franchise',
                      name: 'franchiseEur',
                      type: BusinessAttributeType.number,
                    ),
                  ],
                ),
              ],
              lifecycleStates: const <LifecycleState>[
                LifecycleState(name: 'immobilise', label: 'Immobilisé'),
              ],
            ),
            BusinessObjectSpec(
              id: 'obj_sinistre',
              name: 'Sinistre',
              technicalName: 'Sinistre',
              attributes: <BusinessAttribute>[
                BusinessAttribute(
                  id: 'attr_photos',
                  name: 'photos',
                  type: BusinessAttributeType.object,
                  isArray: true,
                  estimatedMaxRows: 20,
                  children: <BusinessAttribute>[
                    BusinessAttribute(
                      id: 'attr_url',
                      name: 'url',
                      type: BusinessAttributeType.url,
                      required: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
          businessRules: <BusinessRuleSpec>[
            // Règle sur une feature NON validée -> ne doit pas remonter dans usedByValidatedFeatureArtifacts.
            BusinessRuleSpec(
              id: 'rule_rg_301',
              code: 'RG-301',
              title: 'Immobilisation automatique sur sinistre grave',
              targetObjectIds: const <String>['obj_vehicule'],
            ),
          ],
        );

    // FEAT-04 est archivée -> ses objets et artefacts doivent être ignorés partout.
    final feat4Archived =
        SpecFeatureSpec.create(
          id: 'feat_legacy',
          code: 'FEAT-04',
          name: 'Ancien module carburant',
          status: SpecPortfolioStatus.archived,
        ).copyWith(
          businessObjects: <BusinessObjectSpec>[
            BusinessObjectSpec(
              id: 'obj_carte_carburant',
              name: 'Carte carburant',
              technicalName: 'CarteCarburant',
            ),
          ],
        );

    final init = SpecInitiative.create(
      id: 'init_flotte',
      code: 'INIT-01',
      name: 'Mobilité & Flotte',
      features: <SpecFeatureSpec>[
        feat1Validated,
        feat2Active,
        feat3InProgress,
        feat4Archived,
      ],
    );

    return SpecForgeProject.fromIdea(
      id: 'proj_flotte',
      name: 'FleetMaster',
      idea: 'Plateforme de gestion de flotte et autopartage',
    ).copyWith(
      initiatives: <SpecInitiative>[init],
      activeFeatureId: 'feat_resa',
    );
  }

  group('SpecPromptBuilder.buildSiblingFeaturesObjectsDirective', () {
    test('retourne une chaîne vide sur un projet mono-feature ou si seules des features archivées ont des objets', () {
      final single =
          SpecForgeProject.fromIdea(
            idea: 'Application mono-feature',
            name: 'SingleApp',
          ).copyWith(
            businessObjects: <BusinessObjectSpec>[
              BusinessObjectSpec(
                id: 'obj_client',
                name: 'Client',
                technicalName: 'Client',
              ),
            ],
          );
      expect(
        SpecPromptBuilder.buildSiblingFeaturesObjectsDirective(single),
        isEmpty,
      );

      final onlyArchivedSibling =
          SpecForgeProject.fromIdea(
            idea: 'Application avec sœur archivée',
            name: 'ArchivedSiblingApp',
          ).copyWith(
            initiatives: <SpecInitiative>[
              SpecInitiative.create(
                id: 'init_1',
                code: 'INIT-01',
                name: 'Init',
                features: <SpecFeatureSpec>[
                  SpecFeatureSpec.create(
                    id: 'feat_active',
                    code: 'FEAT-01',
                    name: 'Active',
                  ),
                  SpecFeatureSpec.create(
                    id: 'feat_arch',
                    code: 'FEAT-02',
                    name: 'Archivée',
                    status: SpecPortfolioStatus.archived,
                  ).copyWith(
                    businessObjects: <BusinessObjectSpec>[
                      BusinessObjectSpec(
                        id: 'obj_old',
                        name: 'Ancien',
                        technicalName: 'Ancien',
                      ),
                    ],
                  ),
                  SpecFeatureSpec.create(
                    id: 'feat_empty_sibling',
                    code: 'FEAT-03',
                    name: 'Sœur vide',
                  ),
                ],
              ),
            ],
            activeFeatureId: 'feat_active',
          );
      expect(
        SpecPromptBuilder.buildSiblingFeaturesObjectsDirective(
          onlyArchivedSibling,
        ),
        isEmpty,
      );
    });

    test('agrège, dédoublonne et borne le catalogue des features sœurs avec marqueurs Validée et gouvernance additive_warn_on_validated', () {
      final project = buildFleetPortfolioProject();
      final directive = SpecPromptBuilder.buildSiblingFeaturesObjectsDirective(
        project,
      );

      expect(directive, isNotEmpty);
      expect(directive, contains('obj_vehicule'));
      expect(directive, contains('`Vehicule`'));
      expect(directive, contains('FEAT-01 (Validée), FEAT-03 (En cours)'));
      expect(directive, contains('disponible dans les autres features'));
      expect(directive, contains('immatriculation: string!'));
      expect(directive, contains('kilometrage: int'));
      expect(directive, contains('autonomieKm: int'));

      expect(directive, contains('`Conducteur`'));
      expect(directive, contains('déjà présent dans la feature active'));

      expect(directive, contains('`Sinistre`'));
      expect(directive, contains('photos: object[]'));

      // La feature archivée FEAT-04 ne doit jamais apparaître.
      expect(directive, isNot(contains('CarteCarburant')));
      expect(directive, isNot(contains('FEAT-04')));
      // L'objet purement local à la feature active (Reservation) n'est pas listé comme objet sœur.
      expect(directive, isNot(contains('obj_reservation')));

      // Consignes d'architecture obligatoires.
      expect(
        directive,
        contains(
          'POLITIQUE DE PARTAGE INTER-FEATURES — additive_warn_on_validated',
        ),
      );
      expect(directive, contains('FEAT-02 · Réservation collaborateur'));
      expect(directive, contains('list_sibling_features_business_objects'));

      // Vérifie le plafonnement à 20 attributs par objet et 30 objets maximum.
      final manyObjectsSibling =
          SpecFeatureSpec.create(
            id: 'feat_many',
            code: 'FEAT-10',
            name: 'Catalogue massif',
          ).copyWith(
            businessObjects: <BusinessObjectSpec>[
              BusinessObjectSpec(
                id: 'obj_wide',
                name: 'Objet large',
                technicalName: 'WideEntity',
                attributes: <BusinessAttribute>[
                  for (var i = 1; i <= 25; i++)
                    BusinessAttribute(id: 'a_$i', name: 'attr_$i'),
                ],
              ),
              for (var k = 2; k <= 33; k++)
                BusinessObjectSpec(
                  id: 'obj_extra_$k',
                  name: 'Entité $k',
                  technicalName: 'Entity$k',
                ),
            ],
          );
      final cappedProject =
          SpecForgeProject.fromIdea(
            idea: 'Test plafonds',
            name: 'CapApp',
          ).copyWith(
            initiatives: <SpecInitiative>[
              SpecInitiative.create(
                id: 'i1',
                code: 'INIT-01',
                name: 'Init',
                features: <SpecFeatureSpec>[
                  SpecFeatureSpec.create(
                    id: 'feat_act',
                    code: 'FEAT-01',
                    name: 'Active',
                  ),
                  manyObjectsSibling,
                ],
              ),
            ],
            activeFeatureId: 'feat_act',
          );
      final cappedDirective =
          SpecPromptBuilder.buildSiblingFeaturesObjectsDirective(cappedProject);
      expect(cappedDirective, contains('attr_20: string'));
      expect(cappedDirective, isNot(contains('attr_21: string')));
      expect(cappedDirective, contains('(+5 autre(s))'));
      expect(cappedDirective, contains('`Entity30`'));
      expect(cappedDirective, isNot(contains('`Entity31`')));
      expect(cappedDirective, contains('(+3 autre(s) objet(s)'));
    });

    test('injecte la directive dans buildStageKickoffPrompt et buildTurnPrompt aux étapes attendues', () {
      final project = buildFleetPortfolioProject();

      // Kickoff : injecté sur eventStorming et businessObjects, absent sur vision.
      final kickoffEs = SpecPromptBuilder.buildStageKickoffPrompt(
        project,
        SpecForgeStage.eventStorming,
      );
      final kickoffBo = SpecPromptBuilder.buildStageKickoffPrompt(
        project,
        SpecForgeStage.businessObjects,
      );
      final kickoffVision = SpecPromptBuilder.buildStageKickoffPrompt(
        project,
        SpecForgeStage.vision,
      );
      expect(kickoffEs, contains('additive_warn_on_validated'));
      expect(kickoffBo, contains('additive_warn_on_validated'));
      expect(kickoffVision, isNot(contains('additive_warn_on_validated')));

      // Turn prompt : injecté sur eventStorming, businessObjects, exampleMapping, businessRules et reviewExport.
      for (final stage in const <SpecForgeStage>[
        SpecForgeStage.eventStorming,
        SpecForgeStage.businessObjects,
        SpecForgeStage.exampleMapping,
        SpecForgeStage.businessRules,
        SpecForgeStage.reviewExport,
      ]) {
        final turnPrompt = SpecPromptBuilder.buildTurnPrompt(
          project: project,
          stage: stage,
          userInput: 'Vérifie la réutilisation de Vehicule',
          questioningLevel: VibeQuestioningLevel.none,
          afterAskUserReply: false,
        );
        expect(
          turnPrompt,
          contains('additive_warn_on_validated'),
          reason: 'Attendu dans buildTurnPrompt pour ${stage.name}',
        );
      }

      for (final earlyStage in const <SpecForgeStage>[
        SpecForgeStage.lexicon,
        SpecForgeStage.vision,
        SpecForgeStage.specifications,
      ]) {
        final turnPrompt = SpecPromptBuilder.buildTurnPrompt(
          project: project,
          stage: earlyStage,
          userInput: 'Avance le cadrage',
          questioningLevel: VibeQuestioningLevel.none,
          afterAskUserReply: false,
        );
        expect(
          turnPrompt,
          isNot(contains('additive_warn_on_validated')),
          reason: 'Non attendu dans buildTurnPrompt pour ${earlyStage.name}',
        );
      }
    });
  });

  group('SpecForgeToolRegistry — list_sibling_features_business_objects', () {
    test('expose l’outil dans le guide, liste le catalogue sœur, filtre par query avec attributs complets et remonte usedByValidatedFeatureArtifacts', () async {
      final project = buildFleetPortfolioProject();
      final registry = SpecForgeToolRegistry.build(readProject: () => project);

      expect(
        SpecForgeToolRegistry.specToolNames,
        contains('list_sibling_features_business_objects'),
      );
      expect(
        SpecForgeToolRegistry.uxStageToolNames,
        contains('list_sibling_features_business_objects'),
      );
      expect(
        SpecForgeToolRegistry.qaStageToolNames,
        contains('list_sibling_features_business_objects'),
      );
      expect(
        SpecForgeToolRegistry.toolsGuide(),
        contains('`list_sibling_features_business_objects`'),
      );

      // 1. Appel sans argument : liste tous les objets des features sœurs non archivées (mode compact).
      final listCall = VibeToolCall(
        id: 'call_list_all',
        name: 'list_sibling_features_business_objects',
      );
      final listResult = await registry.execute(listCall);
      expect(listResult.isError, isFalse);
      expect(listResult.data['includeFullAttributes'], isFalse);
      expect(listResult.data['objectCount'], 3);
      expect(
        SpecForgeToolRegistry.summarizeResult(listCall, listResult),
        '3 objet(s) métier trouvé(s) dans les features sœurs',
      );

      final listedObjects = (listResult.data['objects'] as List)
          .cast<Map<String, Object?>>();
      expect(
        listedObjects.map((o) => o['technicalName']).toList(),
        const <String>['Vehicule', 'Conducteur', 'Sinistre'],
      );
      final conducteurEntry = listedObjects.firstWhere(
        (o) => o['technicalName'] == 'Conducteur',
      );
      expect(conducteurEntry['presentInActiveFeature'], isTrue);
      final vehiculeCompact = listedObjects.firstWhere(
        (o) => o['technicalName'] == 'Vehicule',
      );
      expect(vehiculeCompact['presentInActiveFeature'], isFalse);
      expect(vehiculeCompact['hasValidatedSiblingFeature'], isTrue);
      expect(vehiculeCompact['attributeSummary'], isA<List<String>>());
      expect(vehiculeCompact.containsKey('attributes'), isFalse);

      // 2. Filtrage ciblé query: 'Vehicule' + includeFullAttributes: true.
      final detailCall = VibeToolCall(
        id: 'call_vehicule',
        name: 'list_sibling_features_business_objects',
        arguments: const <String, Object?>{
          'query': 'Vehicule',
          'includeFullAttributes': true,
        },
      );
      final detailResult = await registry.execute(detailCall);
      expect(detailResult.isError, isFalse);
      expect(detailResult.data['objectCount'], 1);
      expect(
        SpecForgeToolRegistry.summarizeResult(detailCall, detailResult),
        '1 objet(s) métier trouvé(s) dans les features sœurs',
      );

      final vehiculeFull =
          ((detailResult.data['objects'] as List).single)
              as Map<String, Object?>;
      expect(vehiculeFull['id'], 'obj_vehicule');
      expect(vehiculeFull['technicalName'], 'Vehicule');

      final fullAttrs = (vehiculeFull['attributes'] as List)
          .cast<Map<String, Object?>>();
      final attrNames = fullAttrs.map((a) => a['name']).toList();
      expect(
        attrNames,
        containsAll(<String>[
          'immatriculation',
          'kilometrage',
          'motorisation',
          'depotId',
          'contratAssurance',
          'autonomieKm',
        ]),
      );

      final motorisationAttr = fullAttrs.firstWhere(
        (a) => a['name'] == 'motorisation',
      );
      expect(motorisationAttr['type'], 'enumeration');
      expect(motorisationAttr['required'], isTrue);
      expect(motorisationAttr['isArray'], isFalse);
      expect(motorisationAttr['enumValues'], const <String>[
        'thermique',
        'hybride',
        'electrique',
      ]);
      expect(motorisationAttr['children'], isEmpty);

      final depotAttr = fullAttrs.firstWhere((a) => a['name'] == 'depotId');
      expect(depotAttr['referenceObjectId'], 'obj_depot');

      // Fusion récursive des sous-attributs entre FEAT-01 et FEAT-03.
      final contratAttr = fullAttrs.firstWhere(
        (a) => a['name'] == 'contratAssurance',
      );
      final contratChildren = (contratAttr['children'] as List)
          .cast<Map<String, Object?>>();
      expect(contratChildren.map((c) => c['name']).toList(), const <String>[
        'assureur',
        'franchiseEur',
      ]);

      final states = (vehiculeFull['lifecycleStates'] as List)
          .cast<Map<String, Object?>>();
      expect(
        states.map((s) => s['name']).toList(),
        containsAll(<String>['disponible', 'reforme', 'immobilise']),
      );

      // Vérifie usedByValidatedFeatureArtifacts depuis FEAT-01 (Validée) uniquement.
      final validatedDeps =
          (vehiculeFull['usedByValidatedFeatureArtifacts'] as List)
              .cast<Map<String, Object?>>();
      expect(
        validatedDeps.any(
          (d) =>
              d['kind'] == 'businessRule' &&
              d['code'] == 'RG-001' &&
              d['featureCode'] == 'FEAT-01',
        ),
        isTrue,
      );
      expect(
        validatedDeps.any(
          (d) =>
              d['kind'] == 'uxScreen' &&
              d['code'] == 'SCR-001' &&
              d['featureCode'] == 'FEAT-01',
        ),
        isTrue,
      );
      expect(
        validatedDeps.any(
          (d) =>
              d['kind'] == 'qaFixture' &&
              d['code'] == 'FIX-001' &&
              d['featureCode'] == 'FEAT-01',
        ),
        isTrue,
      );
      // RG-301 appartient à FEAT-03 (En cours, non validée) et RG-002 cible Conducteur.
      expect(validatedDeps.any((d) => d['code'] == 'RG-301'), isFalse);
      expect(validatedDeps.any((d) => d['code'] == 'RG-002'), isFalse);

      // 3. Filtre featureCodeOrId + défaut automatique includeFullAttributes=true dès que query est renseigné.
      final scopedCall = VibeToolCall(
        id: 'call_feat3',
        name: 'list_sibling_features_business_objects',
        arguments: const <String, Object?>{
          'featureCodeOrId': 'FEAT-03',
          'query': 'Sinistre',
        },
      );
      final scopedResult = await registry.execute(scopedCall);
      expect(scopedResult.isError, isFalse);
      expect(scopedResult.data['includeFullAttributes'], isTrue);
      expect(scopedResult.data['objectCount'], 1);
      final sinistreObj =
          ((scopedResult.data['objects'] as List).single)
              as Map<String, Object?>;
      expect(sinistreObj['technicalName'], 'Sinistre');
      expect(sinistreObj['usedByValidatedFeatureArtifacts'], isEmpty);
    });
  });
}
