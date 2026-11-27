import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  BusinessObjectSpec buildVehicleObject({
    String id = 'obj_vehicle',
    String description = 'Véhicule du parc automobile.',
    List<BusinessAttribute>? extraAttributes,
  }) => BusinessObjectSpec(
    id: id,
    name: 'Véhicule',
    technicalName: 'Vehicle',
    description: description,
    attributes: <BusinessAttribute>[
      BusinessAttribute(
        id: 'attr_plate',
        name: 'licensePlate',
        type: BusinessAttributeType.string,
        required: true,
      ),
      ...?extraAttributes,
    ],
  );

  group('ObjectSyncSourceKind & FeatureObjectSyncBaseline', () {
    test('valide, normalise en UTC et sérialise une source feature et designDomain', () {
      expect(
        ObjectSyncSourceKind.fromJson('feature'),
        ObjectSyncSourceKind.feature,
      );
      expect(
        ObjectSyncSourceKind.fromJson('Autre Feature'),
        ObjectSyncSourceKind.feature,
      );
      expect(
        ObjectSyncSourceKind.fromJson('designDomain'),
        ObjectSyncSourceKind.designDomain,
      );
      expect(
        ObjectSyncSourceKind.fromJson('design_domain'),
        ObjectSyncSourceKind.designDomain,
      );
      expect(
        ObjectSyncSourceKind.fromJson('Domaine Design'),
        ObjectSyncSourceKind.designDomain,
      );
      expect(
        ObjectSyncSourceKind.fromJson('inconnu'),
        ObjectSyncSourceKind.feature,
      );

      final localSyncTime = DateTime(2026, 11, 27, 21, 15, 30);
      final featureBaseline = FeatureObjectSyncBaseline(
        objectId: 'obj_vehicle',
        sourceKind: ObjectSyncSourceKind.feature,
        sourceFeatureId: 'feat_fleet',
        sourceFeatureCode: 'FEAT-01',
        sourceFeatureName: 'Parc véhicules',
        sourceEntryId: 'obj_src_vehicle',
        syncedAt: localSyncTime,
        baseObject: buildVehicleObject(),
      );

      expect(featureBaseline.syncedAt.isUtc, isTrue);
      expect(featureBaseline.sourceDisplayLabel, 'FEAT-01 · Parc véhicules');
      expect(
        featureBaseline.copyWith(sourceFeatureName: '').sourceDisplayLabel,
        'FEAT-01',
      );
      expect(
        featureBaseline.copyWith(sourceFeatureCode: '').sourceDisplayLabel,
        'Parc véhicules',
      );
      expect(
        featureBaseline
            .copyWith(sourceFeatureCode: '', sourceFeatureName: '')
            .sourceDisplayLabel,
        'Feature',
      );

      featureBaseline.validate();
      final featureJson = featureBaseline.toJson();
      expect(featureJson.containsKey('sourceDomainId'), isFalse);
      final restoredFeatureBaseline = FeatureObjectSyncBaseline.fromJson(
        featureJson,
      );
      expect(restoredFeatureBaseline, equals(featureBaseline));
      expect(
        restoredFeatureBaseline.hashCode,
        equals(featureBaseline.hashCode),
      );

      final designBaseline = FeatureObjectSyncBaseline(
        objectId: 'obj_invoice',
        sourceKind: ObjectSyncSourceKind.designDomain,
        sourceDomainId: 'dom_billing',
        sourceDomainName: 'Facturation',
        sourceEntryId: 'node_customer_invoice',
        syncedAt: DateTime.utc(2026, 11, 27, 20, 0),
        baseObject: BusinessObjectSpec(
          id: 'obj_invoice',
          name: 'Facture',
          technicalName: 'CustomerInvoice',
        ),
      );
      expect(designBaseline.sourceDisplayLabel, 'Design · Facturation');
      expect(
        designBaseline.copyWith(sourceDomainName: '  ').sourceDisplayLabel,
        'Domaine Design',
      );

      designBaseline.validate();
      final designJson = designBaseline.toJson();
      expect(designJson.containsKey('sourceFeatureId'), isFalse);
      final restoredDesignBaseline = FeatureObjectSyncBaseline.fromJson(
        designJson,
      );
      expect(restoredDesignBaseline, equals(designBaseline));
      expect(restoredDesignBaseline.hashCode, equals(designBaseline.hashCode));
    });

    test('rejette les invariants invalides dans validate() et fromJson()', () {
      final valid = FeatureObjectSyncBaseline(
        objectId: 'obj_vehicle',
        sourceKind: ObjectSyncSourceKind.feature,
        sourceFeatureId: 'feat_01',
        syncedAt: DateTime.utc(2026, 11, 27),
        baseObject: buildVehicleObject(),
      );

      expect(
        () => valid.copyWith(objectId: '   ').validate(),
        throwsFormatException,
      );
      expect(
        () => valid.copyWith(sourceFeatureId: '').validate(),
        throwsFormatException,
      );
      expect(
        () => valid
            .copyWith(
              sourceKind: ObjectSyncSourceKind.designDomain,
              sourceDomainId: '',
            )
            .validate(),
        throwsFormatException,
      );
      expect(
        () => FeatureObjectSyncBaseline.fromJson('invalid'),
        throwsFormatException,
      );
      expect(
        () => FeatureObjectSyncBaseline.fromJson(<String, Object?>{
          ...valid.toJson(),
          'sourceKind': 'unknown_kind',
        }),
        throwsFormatException,
      );
      expect(
        () => FeatureObjectSyncBaseline.fromJson(<String, Object?>{
          ...valid.toJson(),
          'syncedAt': 'not-a-date',
        }),
        throwsFormatException,
      );
    });
  });

  group('SpecFeatureSpec.objectSyncBaselines, SpecForgeProject & SpecProjectStore', () {
    test('préserve objectSyncBaselines dans SpecFeatureSpec et SpecForgeProject.copyWith / toJson', () {
      final vehicle = buildVehicleObject();
      final baseline = FeatureObjectSyncBaseline(
        objectId: vehicle.id,
        sourceKind: ObjectSyncSourceKind.feature,
        sourceFeatureId: 'feat_source',
        sourceFeatureCode: 'FEAT-01',
        sourceFeatureName: 'Socle flotte',
        syncedAt: DateTime.utc(2026, 11, 27, 18, 0),
        baseObject: vehicle,
      );

      final emptyFeature = SpecFeatureSpec.create(
        id: 'feat_booking',
        code: 'FEAT-02',
        name: 'Réservation',
      );
      expect(emptyFeature.objectSyncBaselines, isEmpty);
      expect(emptyFeature.toJson().containsKey('objectSyncBaselines'), isFalse);

      final syncedFeature = emptyFeature.copyWith(
        businessObjects: <BusinessObjectSpec>[vehicle],
        objectSyncBaselines: <String, FeatureObjectSyncBaseline>{
          vehicle.id: baseline,
        },
      );
      expect(
        () => syncedFeature.objectSyncBaselines['other'] = baseline,
        throwsUnsupportedError,
      );
      expect(syncedFeature.syncBaselineFor(vehicle.id), equals(baseline));
      expect(syncedFeature.syncBaselineFor('missing'), isNull);
      syncedFeature.validate();

      // Retirer un objet de businessObjects via copyWith ne fait pas échouer validate().
      final afterObjectRemoved = syncedFeature.copyWith(
        businessObjects: const <BusinessObjectSpec>[],
      );
      expect(() => afterObjectRemoved.validate(), returnsNormally);
      expect(afterObjectRemoved.syncBaselineFor(vehicle.id), equals(baseline));

      // Incohérence clé != value.objectId rejetée par validate().
      expect(
        () => emptyFeature
            .copyWith(
              objectSyncBaselines: <String, FeatureObjectSyncBaseline>{
                'wrong_key': baseline,
              },
            )
            .validate(),
        throwsFormatException,
      );

      final restoredFeature = SpecFeatureSpec.fromJson(syncedFeature.toJson());
      expect(restoredFeature, equals(syncedFeature));
      expect(restoredFeature.hashCode, equals(syncedFeature.hashCode));

      // SpecForgeProject.copyWith conserve objectSyncBaselines lors de la mise à jour d'autres champs.
      var project =
          SpecForgeProject.fromIdea(
            id: 'proj_fleet',
            name: 'Flotte',
            idea: 'Gestion de flotte et réservations',
          ).copyWith(
            businessObjects: <BusinessObjectSpec>[vehicle],
            objectSyncBaselines: <String, FeatureObjectSyncBaseline>{
              vehicle.id: baseline,
            },
          );
      expect(project.hasSingleDefaultFeature, isTrue);
      expect(project.objectSyncBaselines[vehicle.id], equals(baseline));

      final enrichedVehicle = buildVehicleObject(
        extraAttributes: <BusinessAttribute>[
          BusinessAttribute(
            id: 'attr_mileage',
            name: 'mileageKm',
            type: BusinessAttributeType.integer,
          ),
        ],
      );
      project = project.copyWith(
        businessObjects: <BusinessObjectSpec>[enrichedVehicle],
      );
      expect(
        project.activeFeature.syncBaselineFor(vehicle.id),
        equals(baseline),
      );

      // Aller-retour JSON mono-fichier d'un projet à feature unique par défaut.
      final restoredSingleProject = SpecForgeProject.fromJson(project.toJson());
      expect(
        restoredSingleProject.activeFeature.objectSyncBaselines,
        equals(project.activeFeature.objectSyncBaselines),
      );
    });

    test('persiste et nettoie spec/object_sync_baselines.json pour un projet mono-feature par défaut', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_sync_single_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final store = SpecProjectStore(tempDir);
      final vehicle = buildVehicleObject();

      var project = SpecForgeProject.fromIdea(
        id: 'proj_single',
        name: 'Location Véhicules',
        idea: 'Location courte durée',
      ).copyWith(businessObjects: <BusinessObjectSpec>[vehicle]);

      await store.saveProject(project);

      final projDirPath =
          '${tempDir.path}${sep}projects${sep}location-vehicules';
      final syncFile = File(
        '$projDirPath${sep}spec${sep}object_sync_baselines.json',
      );
      expect(await syncFile.exists(), isFalse);

      final baseline = FeatureObjectSyncBaseline(
        objectId: vehicle.id,
        sourceKind: ObjectSyncSourceKind.designDomain,
        sourceDomainId: 'dom_fleet',
        sourceDomainName: 'Parc Automobile',
        sourceEntryId: 'entry_vehicle',
        syncedAt: DateTime.utc(2026, 11, 27, 19, 45),
        baseObject: vehicle,
      );
      project = project.copyWith(
        objectSyncBaselines: <String, FeatureObjectSyncBaseline>{
          vehicle.id: baseline,
        },
      );
      await store.saveProject(project);

      expect(await syncFile.exists(), isTrue);
      final rawDisk = jsonDecode(await syncFile.readAsString()) as Map;
      expect(rawDisk['format'], SpecProjectStore.objectSyncBaselinesFormat);

      final freshStore = SpecProjectStore(tempDir);
      final reloaded = await freshStore.loadProject('proj_single');
      expect(reloaded, isNotNull);
      expect(
        reloaded!.activeFeature.syncBaselineFor(vehicle.id),
        equals(baseline),
      );

      // Vidage des baselines -> le fichier optionnel est supprimé du disque.
      final clearedProject = reloaded.copyWith(
        objectSyncBaselines: const <String, FeatureObjectSyncBaseline>{},
      );
      await freshStore.saveProject(clearedProject);
      expect(await syncFile.exists(), isFalse);

      final reloadedCleared = await SpecProjectStore(tempDir)
          .loadProject('proj_single');
      expect(reloadedCleared!.activeFeature.objectSyncBaselines, isEmpty);
    });

    test('persiste et nettoie spec/object_sync_baselines.json sur un portefeuille multi-initiatives / multi-features', () async {
      final tempDir = await Directory.systemTemp.createTemp('ssf_sync_multi_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sep = Platform.pathSeparator;
      final vehicle = buildVehicleObject();
      final invoice = BusinessObjectSpec(
        id: 'obj_invoice',
        name: 'Facture',
        technicalName: 'Invoice',
      );

      final featFleet = SpecFeatureSpec.create(
        id: 'feat_fleet',
        code: 'FEAT-01',
        name: 'Parc véhicules',
      ).copyWith(businessObjects: <BusinessObjectSpec>[vehicle]);

      final fromFleetBaseline = FeatureObjectSyncBaseline(
        objectId: 'obj_booking_vehicle',
        sourceKind: ObjectSyncSourceKind.feature,
        sourceFeatureId: featFleet.id,
        sourceFeatureCode: featFleet.code,
        sourceFeatureName: featFleet.name,
        sourceEntryId: vehicle.id,
        syncedAt: DateTime.utc(2026, 11, 27, 20, 10),
        baseObject: vehicle.copyWith(id: 'obj_booking_vehicle'),
      );
      final fromDesignBaseline = FeatureObjectSyncBaseline(
        objectId: invoice.id,
        sourceKind: ObjectSyncSourceKind.designDomain,
        sourceDomainId: 'dom_billing',
        sourceDomainName: 'Facturation',
        sourceEntryId: 'node_invoice',
        syncedAt: DateTime.utc(2026, 11, 27, 20, 15),
        baseObject: invoice,
      );

      final featBooking =
          SpecFeatureSpec.create(
            id: 'feat_booking',
            code: 'FEAT-02',
            name: 'Réservation & Facturation',
          ).copyWith(
            businessObjects: <BusinessObjectSpec>[
              vehicle.copyWith(id: 'obj_booking_vehicle'),
              invoice,
            ],
            objectSyncBaselines: <String, FeatureObjectSyncBaseline>{
              'obj_booking_vehicle': fromFleetBaseline,
              invoice.id: fromDesignBaseline,
            },
          );

      final initCore = SpecInitiative.create(
        id: 'init_core',
        code: 'INIT-01',
        name: 'Socle Opérationnel',
        features: <SpecFeatureSpec>[featFleet],
      );
      final initCommerce = SpecInitiative.create(
        id: 'init_commerce',
        code: 'INIT-02',
        name: 'Parcours Client',
        features: <SpecFeatureSpec>[featBooking],
      );

      final project = SpecForgeProject(
        id: 'proj_multi_sync',
        name: 'Mobilité Pro',
        initialIdea: 'Plateforme mobilité B2B',
        createdAt: DateTime.utc(2026, 11, 27, 18, 0),
        updatedAt: DateTime.utc(2026, 11, 27, 20, 20),
        initiatives: <SpecInitiative>[initCore, initCommerce],
        activeFeatureId: featBooking.id,
      );

      final store = SpecProjectStore(tempDir);
      await store.saveProject(project);

      final projBase = '${tempDir.path}${sep}projects${sep}mobilite-pro';
      final fleetSyncFile = File(
        '$projBase${sep}initiatives${sep}init-01-socle-operationnel${sep}features${sep}feat-01-parc-vehicules${sep}spec${sep}object_sync_baselines.json',
      );
      final bookingSyncFile = File(
        '$projBase${sep}initiatives${sep}init-02-parcours-client${sep}features${sep}feat-02-reservation-facturation${sep}spec${sep}object_sync_baselines.json',
      );

      // FEAT-01 n'a aucune baseline -> pas de fichier superflu sur disque.
      expect(await fleetSyncFile.exists(), isFalse);
      // FEAT-02 possède 2 baselines -> fichier créé.
      expect(await bookingSyncFile.exists(), isTrue);

      final reloaded = await SpecProjectStore(tempDir)
          .loadProject('proj_multi_sync');
      expect(reloaded, isNotNull);
      expect(reloaded!.featureById(featFleet.id)!.objectSyncBaselines, isEmpty);
      final reloadedBooking = reloaded.featureById(featBooking.id)!;
      expect(reloadedBooking.objectSyncBaselines.length, 2);
      expect(
        reloadedBooking.syncBaselineFor('obj_booking_vehicle'),
        equals(fromFleetBaseline),
      );
      expect(
        reloadedBooking.syncBaselineFor(invoice.id),
        equals(fromDesignBaseline),
      );

      // Suppression des baselines sur FEAT-02 -> nettoyage du fichier sur disque.
      final withoutBookingBaselines = reloaded.updateFeature(
        reloadedBooking.copyWith(
          objectSyncBaselines: const <String, FeatureObjectSyncBaseline>{},
        ),
      );
      await store.saveProject(withoutBookingBaselines);
      expect(await bookingSyncFile.exists(), isFalse);

      final reloadedAfterClear = await SpecProjectStore(tempDir)
          .loadProject('proj_multi_sync');
      expect(
        reloadedAfterClear!.featureById(featBooking.id)!.objectSyncBaselines,
        isEmpty,
      );
    });
  });

  group('SpecFeatureContribution & SpecOriginBaseline multi-features', () {
    test('normalise la contribution initiale, cumule mergeContribution et gère la rétrocompatibilité JSON', () {
      final baseV1 = buildVehicleObject();
      final t1 = DateTime(2026, 11, 27, 10, 0);
      final t2 = DateTime(2026, 11, 27, 14, 30);
      final t3 = DateTime(2026, 11, 27, 17, 45);

      // Normalisation automatique d'une instance construite avec featureId / featureCode seuls.
      final initialOrigin = SpecOriginBaseline(
        projectId: 'proj_mobility',
        projectName: 'Mobilité',
        featureId: 'feat_01',
        featureCode: 'FEAT-01',
        specObjectId: baseV1.id,
        promotedAt: t1,
        baseSpecObject: baseV1,
        ruleFingerprints: const <String, String>{'RG-001': 'fp_rg_001_v1'},
      );

      expect(initialOrigin.contributingFeatures.length, 1);
      expect(initialOrigin.contributingFeatures.single.featureId, 'feat_01');
      expect(initialOrigin.contributingFeatures.single.featureCode, 'FEAT-01');
      expect(initialOrigin.contributingFeatures.single.promotedAt, t1.toUtc());
      expect(initialOrigin.featuresSummaryLabel, 'FEAT-01');

      // Instance sans featureId (projet legacy hors portefeuille) -> liste vide.
      final noFeatureOrigin = SpecOriginBaseline(
        projectId: 'proj_legacy',
        specObjectId: baseV1.id,
        promotedAt: t1,
        baseSpecObject: baseV1,
      );
      expect(noFeatureOrigin.contributingFeatures, isEmpty);
      expect(noFeatureOrigin.featuresSummaryLabel, '');

      // Promotion depuis FEAT-02 enrichissant le même objet Design.
      final baseV2 = buildVehicleObject(
        extraAttributes: <BusinessAttribute>[
          BusinessAttribute(
            id: 'attr_daily_rate',
            name: 'dailyRate',
            type: BusinessAttributeType.number,
          ),
        ],
      );
      final contribFeat2 = SpecFeatureContribution(
        featureId: 'feat_02',
        featureCode: 'FEAT-02',
        featureName: 'Tarification location',
        promotedAt: t2,
      );
      expect(contribFeat2.displayLabel, 'FEAT-02');
      expect(
        contribFeat2.copyWith(featureCode: '').displayLabel,
        'Tarification location',
      );
      expect(
        contribFeat2.copyWith(featureCode: '', featureName: '').displayLabel,
        'feat_02',
      );

      final mergedOrigin = initialOrigin.mergeContribution(
        contribFeat2,
        nextBaseSpecObject: baseV2,
        nextRuleFingerprints: const <String, String>{'RG-010': 'fp_rg_010_v1'},
      );

      expect(mergedOrigin.contributingFeatures.length, 2);
      expect(
        mergedOrigin.contributingFeatures.map((c) => c.featureId).toList(),
        <String>['feat_01', 'feat_02'],
      );
      expect(mergedOrigin.featuresSummaryLabel, 'FEAT-01, FEAT-02');
      expect(mergedOrigin.featureId, 'feat_02');
      expect(mergedOrigin.featureCode, 'FEAT-02');
      expect(mergedOrigin.promotedAt, t2.toUtc());
      expect(mergedOrigin.baseSpecObject, equals(baseV2));
      expect(mergedOrigin.ruleFingerprints, <String, String>{
        'RG-001': 'fp_rg_001_v1',
        'RG-010': 'fp_rg_010_v1',
      });

      // Nouvelle promotion depuis FEAT-01 : dédoublonnage en place sans dupliquer FEAT-01.
      final rePromotedOrigin = mergedOrigin.mergeContribution(
        SpecFeatureContribution(
          featureId: 'feat_01',
          featureCode: 'FEAT-01',
          featureName: 'Parc véhicules (v2)',
          promotedAt: t3,
        ),
        nextBaseSpecObject: baseV2,
        nextRuleFingerprints: const <String, String>{'RG-001': 'fp_rg_001_v2'},
        projectName: 'Mobilité Entreprise',
      );

      expect(rePromotedOrigin.contributingFeatures.length, 2);
      expect(
        rePromotedOrigin.contributingFeatures.first.featureName,
        'Parc véhicules (v2)',
      );
      expect(
        rePromotedOrigin.contributingFeatures.first.promotedAt,
        t3.toUtc(),
      );
      expect(rePromotedOrigin.featureId, 'feat_01');
      expect(rePromotedOrigin.featureCode, 'FEAT-01');
      expect(rePromotedOrigin.promotedAt, t3.toUtc());
      expect(rePromotedOrigin.projectName, 'Mobilité Entreprise');
      expect(rePromotedOrigin.ruleFingerprints['RG-001'], 'fp_rg_001_v2');
      expect(rePromotedOrigin.ruleFingerprints['RG-010'], 'fp_rg_010_v1');

      // Aller-retour JSON complet avec contributingFeatures.
      final serialized = rePromotedOrigin.toJson();
      expect(serialized['contributingFeatures'], isA<List<Object?>>());
      final restored = SpecOriginBaseline.fromJson(serialized);
      expect(restored, equals(rePromotedOrigin));
      expect(restored.hashCode, equals(rePromotedOrigin.hashCode));

      // Rétrocompatibilité d'un JSON legacy sans clé contributingFeatures.
      final legacyJson = <String, Object?>{
        'projectId': 'proj_mobility',
        'projectName': 'Mobilité',
        'featureId': 'feat_01',
        'featureCode': 'FEAT-01',
        'specObjectId': baseV1.id,
        'promotedAt': t1.toUtc().toIso8601String(),
        'baseSpecObject': baseV1.toJson(),
        'ruleFingerprints': <String, String>{'RG-001': 'fp_rg_001_v1'},
      };
      final restoredFromLegacy = SpecOriginBaseline.fromJson(legacyJson);
      expect(restoredFromLegacy, equals(initialOrigin));
      expect(restoredFromLegacy.contributingFeatures.length, 1);
      expect(restoredFromLegacy.featuresSummaryLabel, 'FEAT-01');

      expect(
        () =>
            SpecFeatureContribution(featureId: '  ', promotedAt: t1).validate(),
        throwsFormatException,
      );
    });
  });
}
