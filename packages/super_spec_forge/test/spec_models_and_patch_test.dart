import 'package:flutter_test/flutter_test.dart';
import 'package:super_spec_forge/super_spec_forge.dart';

void main() {
  group('SpecForgeProject & modèles métier', () {
    test('round-trip JSON complet et validation', () {
      final base = SpecForgeProject.fromIdea(
        idea: 'Gestion de flotte automobile d’entreprise',
        name: 'FlotteAuto',
      );
      final enriched = base.copyWith(
        vision: base.vision.copyWith(
          problemStatement: 'Manque de visibilité sur les entretiens',
          objectives: const ['Réduire les pannes de 30%'],
          personas: [
            SpecPersona(
              id: 'persona_gestionnaire',
              name: 'Gestionnaire de flotte',
              role: 'Planifie les entretiens',
              goals: const ['Suivre les échéances'],
            ),
          ],
        ),
        businessObjects: [
          BusinessObjectSpec(
            id: 'obj_vehicule',
            name: 'Véhicule',
            technicalName: 'Vehicule',
            attributes: [
              BusinessAttribute(
                id: 'attr_immat',
                name: 'immatriculation',
                type: BusinessAttributeType.string,
                required: true,
                unique: true,
              ),
            ],
            lifecycleStates: const [
              LifecycleState(name: 'actif', isInitial: true),
              LifecycleState(name: 'reforme', isTerminal: true),
            ],
          ),
        ],
        businessRules: [
          BusinessRuleSpec(
            id: 'rule_rg_001',
            code: 'RG-001',
            title: 'Alerte entretien 15 000 km',
            category: BusinessRuleCategory.trigger,
            targetObjectIds: const ['obj_vehicule'],
            trigger: 'Mise à jour kilométrage',
            condition: 'kmDepuisEntretien >= 15000',
            effect: 'Créer une alerte entretien',
          ),
        ],
      );

      final decoded = SpecForgeProject.fromJson(enriched.toJson());
      expect(decoded, equals(enriched));
      expect(decoded.businessObjects.single.technicalName, 'Vehicule');
      expect(decoded.businessRules.single.code, 'RG-001');
    });

    test('rejette les noms d’attributs incompatibles avec JsonAttributePath', () {
      final invalid = BusinessAttribute(id: 'a1', name: '@calcul');
      expect(invalid.validate, throwsFormatException);

      final invalidDot = BusinessAttribute(id: 'a2', name: 'client.nom');
      expect(invalidDot.validate, throwsFormatException);
    });
  });

  group('SpecStreamParser & SpecPatchApplier', () {
    test('extrait le champ message en streaming puis décode askUser/specPatch', () {
      final parser = SpecStreamParser();
      var snap = parser.addChunk('{"message":"Bonjour ');
      expect(snap.message, 'Bonjour ');
      expect(snap.isMessageComplete, isFalse);

      snap = parser.addChunk('utilisateur\\nSuite","askUser":{"questions":[');
      expect(snap.message, 'Bonjour utilisateur\nSuite');
      expect(snap.isMessageComplete, isTrue);
      expect(snap.hasAskUser, isTrue);

      parser.addChunk(
        '{"id":"q1","title":"Cible ?","type":"single","options":["B2B","B2C"],"default":"B2B"}]},"specPatch":null,"stageReadyToAdvance":false}',
      );
      final resp = SpecAgentResponse.parse(parser.rawText);
      expect(resp.message, 'Bonjour utilisateur\nSuite');
      expect(resp.askUser, isNotNull);
      expect(resp.askUser!.questions.single.options, ['B2B', 'B2C']);
      expect(resp.specPatch, isNull);
    });

    test('fusionne incrémentalement et supprime par ID via SpecPatchApplier', () {
      final project = SpecForgeProject.fromIdea(
        idea: 'Suivi de commandes clients',
        name: 'OrderHub',
      );
      final res1 = SpecPatchApplier.apply(project, {
        'vision': {
          'objectives': ['Automatiser la validation'],
          'personas': [
            {'id': 'p1', 'name': 'Commercial', 'role': 'Saisit les commandes'},
          ],
        },
        'businessObjects': [
          {
            'id': 'obj_cmd',
            'name': 'Commande',
            'technicalName': 'Commande',
            'attributes': [
              {'id': 'a1', 'name': 'numero', 'type': 'string', 'required': true},
            ],
          },
        ],
        'businessRules': [
          {
            'id': 'r1',
            'code': 'RG-001',
            'title': 'Numéro obligatoire',
            'targetObjectIds': ['obj_cmd'],
          },
          {
            'id': 'r2',
            'code': 'RG-002',
            'title': 'Temporaire',
            'targetObjectIds': ['obj_cmd'],
          },
        ],
      });

      expect(res1.project.vision.personas.length, 1);
      expect(res1.project.businessObjects.length, 1);
      expect(res1.project.businessRules.length, 2);

      final res2 = SpecPatchApplier.apply(res1.project, {
        'removeBusinessRuleIds': ['r2'],
        'businessRules': [
          {
            'id': 'r1',
            'code': 'RG-001',
            'title': 'Numéro unique et obligatoire',
            'targetObjectIds': ['obj_cmd'],
          },
        ],
      });

      expect(res2.project.businessRules.length, 1);
      expect(
        res2.project.businessRules.single.title,
        'Numéro unique et obligatoire',
      );
    });
  });
}
