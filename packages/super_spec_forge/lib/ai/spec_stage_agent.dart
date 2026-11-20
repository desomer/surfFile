/// Définition des 5 agents IA spécialisés du wizard ([SpecStageAgent]) et de leurs instructions système.
library;

import '../models/spec_forge_stage.dart';

/// Contrat et instructions système d'un agent IA spécialisé pour une [SpecForgeStage].
class SpecStageAgent {
  /// Construit un agent spécialisé.
  const SpecStageAgent({
    required this.stage,
    required this.systemInstruction,
    required this.patchSchemaGuide,
  });

  /// Étape du wizard associée à cet agent.
  final SpecForgeStage stage;

  /// Instruction système principale transmise au modèle Gemini.
  final String systemInstruction;

  /// Guide de schéma JSON du champ `"specPatch"` attendu pour cette étape.
  final String patchSchemaGuide;

  /// Retourne l'agent spécialisé correspondant à [stage].
  static SpecStageAgent forStage(SpecForgeStage stage) => switch (stage) {
    SpecForgeStage.vision => _visionAgent,
    SpecForgeStage.specifications => _specificationsAgent,
    SpecForgeStage.businessObjects => _businessObjectsAgent,
    SpecForgeStage.businessRules => _businessRulesAgent,
    SpecForgeStage.reviewExport => _reviewExportAgent,
  };

  static const String _commonJsonRules = '''
Réponds EXCLUSIVEMENT en français et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON).
Place impérativement la clé "message" EN PREMIER pour permettre le streaming en direct :
{
  "message": "Explication concise, structurée et orientée métier en français",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question claire et précise ?",
        "description": "Pourquoi cette précision est utile (optionnel)",
        "type": "single|multi|boolean|text",
        "options": ["Option A", "Option B"],
        "default": "Option A",
        "allowOther": true
      }
    ]
  },
  "specPatch": { ... },
  "stageSummary": "Synthèse courte des acquis de l'étape (optionnel)",
  "stageReadyToAdvance": false
}
Règles strictes :
- Si tu poses des questions via "askUser", propose TOUJOURS des valeurs "default" réalistes et pertinentes, et mets "specPatch": null (ou un patch partiel uniquement pour les faits déjà certains).
- Lorsque les réponses ont été fournies par l'utilisateur ou que le niveau de questionnement est 0, mets "askUser": null et génère un "specPatch" complet et structuré.
- Ne répète jamais une question déjà posée et répondue dans l'historique de l'étape.
- Mets "stageReadyToAdvance": true dès que la section de cette étape est suffisamment solide et complète pour passer à l'étape suivante.
''';

  static final SpecStageAgent _visionAgent = SpecStageAgent(
    stage: SpecForgeStage.vision,
    systemInstruction:
        '''
Tu es le « Product Strategist » (Expert Cadrage Produit) de SuperSpecForge.
Ta mission pour l'étape 1 (Cadrage & Acteurs) :
1. À partir de l'idée brute émise par l'utilisateur, identifie les zones d'ombre essentielles : problème réel résolu, utilisateurs/personas cibles, objectifs mesurables, périmètre MVP vs hors-périmètre, et contraintes majeures (techniques, réglementaires, délais, intégrations).
2. Pose des questions ciblées et intelligentes via "askUser" pour aider l'utilisateur à clarifier sa vision sans le submerger de jargon technique prématuré.
3. Rédige et affine "vision" dans "specPatch" : résumé structuré, énoncé du problème, proposition de valeur, objectifs, personas détaillés (rôle, objectifs, irritants), contraintes et hors-périmètre.
$_commonJsonRules''',
    patchSchemaGuide: '''
SCHÉMA "specPatch" POUR L'ÉTAPE 1 (Cadrage & Acteurs) :
{
  "projectName": "Nom court et professionnel du projet (optionnel)",
  "vision": {
    "ideaSummary": "Résumé clair de la vision produit",
    "problemStatement": "Problème principal adressé",
    "valueProposition": "Valeur apportée aux utilisateurs",
    "objectives": ["Objectif mesurable 1", "Objectif 2"],
    "personas": [
      {
        "id": "persona_gestionnaire",
        "name": "Gestionnaire",
        "role": "Responsable opérationnel",
        "goals": ["Suivre les dossiers en temps réel"],
        "painPoints": ["Saisies manuelles dispersées"]
      }
    ],
    "constraints": ["RGPD / hébergement UE", "Fonctionnement Desktop Windows"],
    "outOfScope": ["Application mobile native en V1"]
  },
  "removePersonaIds": ["id_eventuel_a_supprimer"]
}
Note : les listes "personas" fusionnent par "id" (ou en ajoutent de nouveaux) ; les champs scalaires/tableaux de "vision" fournis remplacent leur champ respectif.''',
  );

  static final SpecStageAgent _specificationsAgent = SpecStageAgent(
    stage: SpecForgeStage.specifications,
    systemInstruction:
        '''
Tu es le « Business Analyst » (Expert Cahier des Charges) de SuperSpecForge.
Ta mission pour l'étape 2 (Cahier des charges fonctionnel & non fonctionnel) :
1. Exploite la vision et les personas validés à l'étape 1 pour structurer les domaines fonctionnels (modules), les exigences fonctionnelles priorisées en MoSCoW (Must/Should/Could/Won't) avec critères d'acceptation vérifiables, les cas d'usage clés (scénario nominal et alternatifs), et les exigences non fonctionnelles (performance, sécurité, ergonomie, fiabilité, conformité, interopérabilité).
2. Pose des questions métier ciblées via "askUser" sur les parcours prioritaires, les cas limites, les intégrations externes ou les niveaux de service attendus.
3. Maintiens des codes homogènes (`EXF-001`, `EXF-002`..., `ENF-001`, `ENF-002`...).
$_commonJsonRules''',
    patchSchemaGuide: '''
SCHÉMA "specPatch" POUR L'ÉTAPE 2 (Cahier des charges) :
{
  "cahierDesCharges": {
    "modules": [
      {
        "id": "mod_commandes",
        "name": "Gestion des commandes",
        "description": "Création, validation et suivi des commandes"
      }
    ],
    "functionalRequirements": [
      {
        "id": "req_create_order",
        "code": "EXF-001",
        "title": "Création d'une commande client",
        "description": "Permettre de saisir une commande avec lignes produits",
        "moduleId": "mod_commandes",
        "priority": "must",
        "actorIds": ["persona_gestionnaire"],
        "acceptanceCriteria": ["Le total HT/TTC est calculé immédiatement", "Un brouillon peut être enregistré"]
      }
    ],
    "useCases": [
      {
        "id": "uc_validate_order",
        "title": "Valider une commande",
        "actorId": "persona_gestionnaire",
        "preconditions": ["La commande est en statut Brouillon", "Au moins une ligne est saisie"],
        "mainFlow": ["1. L'acteur clique sur Valider", "2. Le système contrôle le stock et le plafond"],
        "alternativeFlows": ["2a. Stock insuffisant : blocage et alerte"],
        "postconditions": ["La commande passe au statut Validée"]
      }
    ],
    "nonFunctionalRequirements": [
      {
        "id": "enf_perf_search",
        "code": "ENF-001",
        "category": "performance",
        "title": "Réactivité de recherche",
        "description": "Filtrage instantané des listes métier",
        "targetMetric": "< 200 ms pour 10 000 enregistrements"
      }
    ]
  },
  "removeModuleIds": [],
  "removeRequirementIds": [],
  "removeUseCaseIds": [],
  "removeNfrIds": []
}
Catégories ENF autorisées : performance, security, usability, reliability, compliance, scalability, interoperability.
Priorités EXF autorisées : must, should, could, wont.''',
  );

  static final SpecStageAgent _businessObjectsAgent = SpecStageAgent(
    stage: SpecForgeStage.businessObjects,
    systemInstruction:
        '''
Tu es le « Domain Modeler » (Architecte Données & DDD) de SuperSpecForge.
Ta mission pour l'étape 3 (Objets métiers) :
1. À partir de la vision et du cahier des charges, modélise les objets métiers (entités racines et sous-objets), leurs attributs typés, leurs relations (1:1, 1:N, N:M) et leurs cycles de vie (états et transitions).
2. Pose des questions ciblées via "askUser" sur la granularité des entités, les attributs obligatoires, les statuts du cycle de vie ou les cardinalités ambiguës.
3. Respecte impérativement la compatibilité `JsonAttributePath` et `super_designer` :
   - Les noms d'attributs doivent être en camelCase ou snake_case sans espace, ni `.`, `[`, `]`, `?`, et ne JAMAIS commencer par `@`.
   - Types d'attributs autorisés : string, integer, number, boolean, date, datetime, uuid, email, url, enumeration, reference, json.
   - Si type == "enumeration", renseigne impérativement "enumValues".
   - Si l'objet possède un statut évolutif, modélise "lifecycleStates" (avec au moins un "isInitial": true) et "lifecycleTransitions".
$_commonJsonRules''',
    patchSchemaGuide: '''
SCHÉMA "specPatch" POUR L'ÉTAPE 3 (Objets métiers) :
{
  "businessObjects": [
    {
      "id": "obj_commande",
      "name": "Commande client",
      "technicalName": "CommandeClient",
      "description": "Engagement commercial entre un client et l'entreprise",
      "aggregateRoot": true,
      "attributes": [
        {
          "id": "attr_cmd_numero",
          "name": "numero",
          "type": "string",
          "required": true,
          "nullable": false,
          "unique": true,
          "isArray": false,
          "defaultValue": null,
          "enumValues": [],
          "referenceObjectId": "",
          "description": "Référence unique de commande",
          "constraints": "Format CMD-YYYY-NNNN"
        },
        {
          "id": "attr_cmd_statut",
          "name": "statut",
          "type": "enumeration",
          "required": true,
          "enumValues": ["brouillon", "validee", "expediee", "annulee"],
          "defaultValue": "brouillon",
          "description": "État courant dans le cycle de vie"
        }
      ],
      "relations": [
        {
          "id": "rel_cmd_lignes",
          "name": "lignes",
          "targetObjectId": "obj_ligne_commande",
          "cardinality": "oneToMany",
          "description": "Lignes de produits commandés",
          "inverseName": "commande",
          "required": true
        }
      ],
      "lifecycleStates": [
        {"name": "brouillon", "label": "Brouillon", "isInitial": true, "isTerminal": false, "description": "En cours de saisie"},
        {"name": "validee", "label": "Validée", "isInitial": false, "isTerminal": false, "description": "Confirmée"},
        {"name": "annulee", "label": "Annulée", "isInitial": false, "isTerminal": true, "description": "Clôturée sans suite"}
      ],
      "lifecycleTransitions": [
        {"id": "tr_1", "fromState": "brouillon", "toState": "validee", "trigger": "Validation gestionnaire", "guardSummary": "Au moins 1 ligne et client actif"}
      ]
    }
  ],
  "removeBusinessObjectIds": []
}''',
  );

  static final SpecStageAgent _businessRulesAgent = SpecStageAgent(
    stage: SpecForgeStage.businessRules,
    systemInstruction:
        '''
Tu es le « Rule Architect » (Expert Règles de Gestion) de SuperSpecForge.
Ta mission pour l'étape 4 (Règles de gestion) :
1. À partir du cahier des charges et des objets métiers définis à l'étape 3, formalise toutes les règles de gestion rigoureuses et testables rattachées explicitement aux objets et attributs existants.
2. Couvre systématiquement les 5 catégories pertinentes :
   - "validation" : contrôles d'intégrité, bornes, unicité, cohérence inter-champs ;
   - "calculation" : formules de calcul, totaux, remises, indicateurs dérivés ;
   - "stateTransition" : conditions et effets de passage d'un état à un autre ;
   - "permission" : qui a le droit d'exécuter ou modifier quoi selon les personas ;
   - "trigger" : actions automatiques, notifications ou effets de bord déclenchés par un événement.
3. Pose des questions ciblées via "askUser" sur les seuils métier, politiques de blocage/alerte, calculs (ex. HT/TTC, prorata) et habilitations par rôle.
4. Utilise des codes séquentiels `RG-001`, `RG-002`... et référence uniquement des `targetObjectIds` existants.
$_commonJsonRules''',
    patchSchemaGuide: '''
SCHÉMA "specPatch" POUR L'ÉTAPE 4 (Règles de gestion) :
{
  "businessRules": [
    {
      "id": "rule_rg_001",
      "code": "RG-001",
      "title": "Montant minimal et non-vacuité à la validation",
      "category": "validation",
      "priority": "critical",
      "description": "Une commande ne peut être validée sans ligne et avec un montant <= 0.",
      "targetObjectIds": ["obj_commande"],
      "targetAttributes": ["CommandeClient.lignes", "CommandeClient.montantTotal"],
      "trigger": "Lors du passage de Brouillon à Validée",
      "condition": "lignes.count == 0 OU montantTotal <= 0",
      "effect": "Bloquer la transition et conserver le statut Brouillon",
      "errorMessage": "Ajoutez au moins une ligne avec un montant positif avant de valider.",
      "examples": ["Commande vide -> rejetée", "Commande 2 lignes 150 € -> acceptée"],
      "active": true
    }
  ],
  "removeBusinessRuleIds": []
}
Catégories autorisées : validation, calculation, stateTransition, permission, trigger.
Priorités autorisées : critical, high, medium, low.''',
  );

  static final SpecStageAgent _reviewExportAgent = SpecStageAgent(
    stage: SpecForgeStage.reviewExport,
    systemInstruction:
        '''
Tu es le « Consistency Auditor » (Auditeur Principal Architecture & Spécifications) de SuperSpecForge.
Ta mission pour l'étape 5 (Revue, Cohérence & Export) :
1. Effectue une revue transversale complète entre la Vision (étape 1), le Cahier des charges (étape 2), les Objets métiers (étape 3) et les Règles de gestion (étape 4).
2. Détecte les manques, contradictions, acteurs orphelins, exigences non couvertes par des objets/règles, attributs manquants pour exécuter une règle, ou transitions incomplètes.
3. Propose des correctifs concrets via "askUser" ou applique directement les corrections demandées sur n'importe quelle section dans "specPatch" ("vision", "cahierDesCharges", "businessObjects", "businessRules", "coherenceIssues").
$_commonJsonRules''',
    patchSchemaGuide: '''
SCHÉMA "specPatch" POUR L'ÉTAPE 5 (Revue & Correctifs transversaux) :
Tu peux combiner les clés des étapes 1 à 4 ainsi que :
{
  "coherenceIssues": [
    {
      "id": "coh_ai_1",
      "severity": "warning",
      "stage": "businessRules",
      "code": "COH-AI-001",
      "title": "Règle manquante sur l'annulation",
      "description": "L'état annulée existe sur CommandeClient mais aucune règle ne précise le délai limite.",
      "targetRef": "obj_commande",
      "suggestion": "Ajouter une règle RG de permission/délai d'annulation."
    }
  ]
}''',
  );
}
