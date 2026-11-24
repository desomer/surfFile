/// Registre des outils IA métier et de diagnostic pour `super_spec_forge` ([SpecForgeToolRegistry]).
///
/// Réutilise les contrats [VibeAppToolRegistry], [VibeToolDeclaration],
/// [VibeToolCall] et [VibeToolResult] de `super_container_layout`.
library;

import 'dart:math' as math;

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/cost/cost_coherence_issue.dart';
import '../models/cost/cost_forge_spec.dart';
import '../models/cost/cost_forge_stage.dart';
import '../models/cost/cost_run_item_spec.dart';
import '../models/cost/cost_wbs_item_spec.dart';
import '../models/enterprise_rate_card.dart';
import '../models/event_storming_spec.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/qa/gherkin_feature_spec.dart';
import '../models/qa/qa_coherence_issue.dart';
import '../models/qa/qa_forge_spec.dart';
import '../models/qa/qa_forge_stage.dart';
import '../models/qa/tdd_suite_spec.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_screen_spec.dart';
import '../services/exporters/event_storming_dsl_codec.dart';
import '../services/spec_coherence_analyzer.dart';
import '../services/spec_schema_dsl_bridge.dart';

/// Construit et documente les outils exposés aux agents IA de `super_spec_forge`.
abstract final class SpecForgeToolRegistry {
  /// Ensemble des outils du wizard de spécification métier.
  static const Set<String> specToolNames = <String>{
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'get_event_storming',
    'inspect_business_object',
    'get_example_mapping',
    'get_business_rules',
    'get_debug_entries',
    'run_coherence_audit',
    'validate_yaml_light_schema',
    'extract_array_to_business_object',
    'focus_stage_or_object',
    'filter_business_objects',
  };

  /// Ensemble des 4 outils dédiés au volet de conception UX.
  static const Set<String> uxToolNames = <String>{
    'get_ux_overview',
    'inspect_ux_screen',
    'run_ux_coherence_audit',
    'focus_ux_item',
  };

  /// Ensemble recommandé d'outils pour les 4 agents du wizard UX (outils UX + introspection Spec en lecture/audit).
  static const Set<String> uxStageToolNames = <String>{
    'get_ux_overview',
    'inspect_ux_screen',
    'run_ux_coherence_audit',
    'focus_ux_item',
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'inspect_business_object',
    'get_business_rules',
    'run_coherence_audit',
    'get_debug_entries',
  };

  /// Ensemble des 4 outils dédiés au volet QA BDD/Gherkin & TDD.
  static const Set<String> qaToolNames = <String>{
    'get_qa_overview',
    'inspect_qa_artifact',
    'run_qa_coherence_audit',
    'focus_qa_item',
  };

  /// Ensemble recommandé d'outils pour les 4 agents du wizard QA (outils QA + introspection UX & Spec en lecture/audit).
  static const Set<String> qaStageToolNames = <String>{
    'get_qa_overview',
    'inspect_qa_artifact',
    'run_qa_coherence_audit',
    'focus_qa_item',
    'get_ux_overview',
    'inspect_ux_screen',
    'run_ux_coherence_audit',
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'inspect_business_object',
    'get_example_mapping',
    'get_business_rules',
    'run_coherence_audit',
    'get_debug_entries',
  };

  /// Ensemble des 3 outils dédiés au volet FinOps & Chiffrage.
  static const Set<String> costToolNames = <String>{
    'get_cost_overview',
    'inspect_cost_item',
    'focus_cost_item',
  };

  /// Ensemble recommandé d'outils pour les 4 agents du wizard FinOps & Chiffrage (outils Coûts + introspection Spec/UX/QA en lecture/audit).
  static const Set<String> costStageToolNames = <String>{
    'get_cost_overview',
    'inspect_cost_item',
    'focus_cost_item',
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'get_event_storming',
    'inspect_business_object',
    'get_business_rules',
    'get_ux_overview',
    'inspect_ux_screen',
    'get_qa_overview',
    'inspect_qa_artifact',
    'run_coherence_audit',
    'get_debug_entries',
  };

  /// Ligne de guide (nom → rôle) de chaque outil, dans l'ordre de [declarations].
  static const List<(String, String)> _toolGuideLines = <(String, String)>[
    (
      'get_lexicon_and_synonyms',
      'recherche les termes canoniques, définitions et synonymes rejetés dans le lexique métier.',
    ),
    (
      'get_requirements_summary',
      'liste les modules, exigences fonctionnelles (EXF), cas d\'usage et exigences non fonctionnelles (ENF).',
    ),
    (
      'get_event_storming',
      'lit les Bounded Contexts et flux Event Storming (événements domaine, commandes, acteurs, agrégats, politiques, read models et hotspots).',
    ),
    (
      'inspect_business_object',
      'lit le détail complet d\'un objet métier (sous-objets, attributs, compteur N/200, tableaux, relations, cycle de vie, YAML Light).',
    ),
    (
      'get_example_mapping',
      'lit les tableaux d\'Example Mapping (Story jaune, règles bleues, exemples verts et questions rouges), filtrables par objet métier ou code EM-xxx.',
    ),
    (
      'get_business_rules',
      'liste les règles de gestion RG-xxx existantes (filtrables par objet ou catégorie).',
    ),
    (
      'get_debug_entries',
      'consulte les derniers journaux et erreurs capturés dans la console debug.',
    ),
    (
      'run_coherence_audit',
      'exécute l\'analyse de cohérence inter-étapes et signale références cassées ou dépassements > 200.',
    ),
    (
      'validate_yaml_light_schema',
      'valide un bloc YAML Light via Yaml2JsonSchemasParser et vérifie les règles <= 200 attributs / <= 200 lignes/tableau.',
    ),
    (
      'extract_array_to_business_object',
      'extrait un tableau imbriqué vers un nouvel objet métier dédié relié en 1:N.',
    ),
    (
      'focus_stage_or_object',
      'bascule l\'interface sur une étape du wizard et sélectionne éventuellement un objet métier cible et/ou un attribut précis (`attributePath`, ex. `statut` ou `adresseLivraison.codePostal`).',
    ),
    (
      'filter_business_objects',
      'filtre les objets métiers et attributs affichés dans « Arbre & Inspecteur » (ou efface le filtre avec `query: ""`).',
    ),
    (
      'get_ux_overview',
      'synthétise les parcours utilisateurs (`JRN-xxx`), le shell applicatif, le thème visuel Material 3, les routes (`UxRouteNode`) et les écrans (`SCR-xxx`).',
    ),
    (
      'inspect_ux_screen',
      'lit le détail complet d\'un écran UX (`UxScreenSpec`) ou d\'un parcours utilisateur (`UxJourneySpec`) par identifiant, code (`SCR-001` / `JRN-001`), `routeId` ou nom.',
    ),
    (
      'run_ux_coherence_audit',
      'exécute l\'audit de cohérence et de traçabilité Métier↔UX (personas, EXF, cas d\'usage, routes, objets/attributs et règles `RG-xxx`).',
    ),
    (
      'focus_ux_item',
      'positionne l\'atelier UX sur une étape, un parcours (`journeyId`), une route (`routeId`), un écran (`screenId`) et/ou une zone (`zone`).',
    ),
    (
      'get_qa_overview',
      'synthétise les jeux d\'essais (`FIX-xxx`), les features et scénarios Gherkin (`FEAT-xxx` / `SCN-xxx`), les suites et cas TDD (`TDD-xxx` / `TC-xxx`) et la langue Gherkin active (`fr` / `en`).',
    ),
    (
      'inspect_qa_artifact',
      'lit le détail complet d\'une fixture (`QaFixtureSpec`), d\'une feature ou d\'un scénario Gherkin (`GherkinFeatureSpec` / `GherkinScenarioSpec`) ou d\'une suite TDD (`TddTestSuiteSpec`) par identifiant, code (`FIX-001`, `FEAT-001`, `SCN-001`, `TDD-001`) ou nom/titre.',
    ),
    (
      'run_qa_coherence_audit',
      'exécute l\'audit de couverture 360° et de cohérence Métier+UX↔QA (couverture `EXF-xxx` / `RG-xxx`, variables `<var>` d\'Exemples Gherkin, erreurs attendues TDD et références croisées).',
    ),
    (
      'focus_qa_item',
      'positionne l\'atelier QA sur une étape (`stage`), une fixture (`fixtureId`), une feature (`featureId`), un scénario (`scenarioId`) et/ou une suite TDD (`tddSuiteId`).',
    ),
    (
      'get_cost_overview',
      'synthétise le volet FinOps & Chiffrage : hypothèses TJM, Build WBS CAPEX (MVP / V1 / Cible, PERT & P80, Classique vs IA), Run OPEX sur 1/3/5 ans, provision risques EMV, TCO 1/3/5 ans et diagnostics de cohérence.',
    ),
    (
      'inspect_cost_item',
      'lit le détail complet d\'un profil TJM (`PRF-xxx`), d\'un lot Build WBS (`WBS-xxx`), d\'un poste Run OPEX (`RUN-xxx`) ou d\'un risque budgétaire (`RSK-xxx`) par identifiant, code ou nom/titre.',
    ),
    (
      'focus_cost_item',
      'positionne l\'atelier FinOps & Chiffrage sur une étape (`stage`), un profil TJM (`profileId`), un lot WBS (`wbsItemId`), un poste Run (`runItemId`) et/ou un risque (`riskItemId`).',
    ),
  ];

  /// Guide succinct injecté dans le guide statique des agents, restreint aux
  /// outils [toolNames] lorsqu'il est fourni (numérotation recalculée).
  static String toolsGuide({Set<String>? toolNames}) {
    final lines = [
      for (final (name, role) in _toolGuideLines)
        if (toolNames == null || toolNames.contains(name)) '`$name` : $role',
    ];
    return [
      'OUTILS D\'INTROSPECTION, VALIDATION ET ACTION DISPONIBLES :',
      for (var i = 0; i < lines.length; i++) '${i + 1}. ${lines[i]}',
      'Utilise ces outils à bon escient avant de conclure lorsque tu as besoin de vérifier des détails, valider un schéma ou auditer la cohérence.',
    ].join('\n');
  }

  /// Déclarations statiques des outils (Spec, UX, QA et FinOps/Coûts) exposés au modèle Gemini.
  static const List<VibeToolDeclaration> declarations = <VibeToolDeclaration>[
    VibeToolDeclaration(
      name: 'get_lexicon_and_synonyms',
      description: 'Consulte le lexique métier (termes canoniques, définitions, synonymes à unifier, conventions).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': 'Filtre texte optionnel sur le terme, la définition ou un synonyme.',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_requirements_summary',
      description: 'Liste les modules, exigences fonctionnelles (EXF), cas d’usage et exigences non fonctionnelles (ENF) du cahier des charges.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'moduleId': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant de module.',
          },
          'priority': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par priorité MoSCoW (must, should, could, wont).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_event_storming',
      description: 'Consulte les documents Event Storming DSL v1.0 (1 document .es.yaml par Bounded Context : meta, catalog ACT/AGG/EXT, flow d’étapes avec triggered_by, policy, read_model, command, domain_event/outcomes, hotspots et backlog).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'documentIdOrContext': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant, fichier .es.yaml ou nom de Bounded Context.',
          },
          'onlyOpenHotspots': <String, Object?>{
            'type': 'boolean',
            'description': 'Retourne uniquement les Bounded Contexts ayant au moins un hotspot ouvert (false par défaut).',
          },
          'includeYaml': <String, Object?>{
            'type': 'boolean',
            'description': 'Inclut le rendu YAML .es.yaml de chaque document filtré (false par défaut).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'inspect_business_object',
      description: 'Retourne le détail complet d’un objet métier (sous-objets, compteur N/200 attributs, tableaux imbriqués, relations, cycle de vie et YAML Light optionnel), ou la liste synthétique si objectIdOrName est omis.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'objectIdOrName': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, nom technique ou nom métier de l’objet à inspecter.',
          },
          'includeYaml': <String, Object?>{
            'type': 'boolean',
            'description': 'Inclut la représentation YAML Light du projet ou de l’objet (false par défaut).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_example_mapping',
      description: 'Consulte les tableaux d’Example Mapping à 4 couleurs (stories jaunes, règles bleues, exemples verts et questions rouges), filtrables par objet métier, code EM-xxx ou questions ouvertes.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant ou nom technique d’objet métier cible.',
          },
          'storyIdOrCode': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant ou code EM-xxx de story.',
          },
          'onlyOpenQuestions': <String, Object?>{
            'type': 'boolean',
            'description': 'Ne retourne que les stories contenant au moins une question rouge ouverte (false par défaut).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_business_rules',
      description: 'Liste les règles de gestion RG-xxx existantes, filtrables par objet cible ou catégorie.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant ou nom technique d’objet cible.',
          },
          'category': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel (validation, calculation, stateTransition, permission, trigger).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_debug_entries',
      description: 'Lit les derniers journaux et erreurs capturés dans la console debug (debugEntries).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'type': <String, Object?>{
            'type': 'string',
            'description':
                'Filtre optionnel : error, log ou all (error par défaut).',
          },
          'query': <String, Object?>{
            'type': 'string',
            'description': 'Filtre texte optionnel dans le message ou la pile.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'description':
                'Nombre maximal d’entrées retournées (1..50, 20 par défaut).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'run_coherence_audit',
      description: 'Exécute l’analyse de cohérence statique inter-étapes sur l’ensemble du projet (références cassées, états manquants, limites > 200).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
    VibeToolDeclaration(
      name: 'validate_yaml_light_schema',
      description: 'Valide un schéma YAML « JSON Schemas Light » via Yaml2JsonSchemasParser et vérifie les règles <= 200 attributs et <= 200 lignes par tableau.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'yaml': <String, Object?>{
            'type': 'string',
            'description': 'Source YAML Light à parser et valider.',
          },
        },
        'required': <String>['yaml'],
      },
    ),
    VibeToolDeclaration(
      name: 'extract_array_to_business_object',
      description: 'Extrait un attribut tableau d’un objet métier vers un nouvel objet métier dédié relié en 1:N (recommandé dès > 200 lignes fonctionnelles).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou nom technique de l’objet parent.',
          },
          'attributeName': <String, Object?>{
            'type': 'string',
            'description': 'Nom de l’attribut tableau à extraire.',
          },
          'newObjectName': <String, Object?>{
            'type': 'string',
            'description': 'Nom du nouvel objet métier dédié (optionnel).',
          },
        },
        'required': <String>['objectId', 'attributeName'],
      },
    ),
    VibeToolDeclaration(
      name: 'focus_stage_or_object',
      description: 'Positionne l’interface du wizard sur une étape donnée et sélectionne éventuellement un objet métier ainsi qu’un attribut (ou sous-attribut) dans l’inspecteur.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Nom de l’étape (lexicon, vision, specifications, eventStorming, businessObjects, exampleMapping, businessRules, reviewExport).',
          },
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, nom technique ou nom métier de l’objet à sélectionner (optionnel).',
          },
          'attributePath': <String, Object?>{
            'type': 'string',
            'description': 'Nom ou chemin pointé de l’attribut à sélectionner dans l’objet (ex. "statut" ou "adresseLivraison.codePostal").',
          },
          'eventStormFlowId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code ES-xxx du flux Event Storming à sélectionner (optionnel).',
          },
          'exampleStoryId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code EM-xxx du tableau Example Mapping à sélectionner (optionnel).',
          },
        },
        'required': <String>['stage'],
      },
    ),
    VibeToolDeclaration(
      name: 'filter_business_objects',
      description: 'Filtre l’arbre des objets métiers et attributs dans « Arbre & Inspecteur » selon une requête texte, ou efface le filtre si query est vide.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'description': 'Mot-clé de filtre sur nom d’objet, alias, nom d’attribut ou type (chaîne vide pour tout réafficher).',
          },
        },
        'required': <String>['query'],
      },
    ),
    VibeToolDeclaration(
      name: 'get_ux_overview',
      description: 'Retourne un aperçu synthétique du volet UX : parcours utilisateurs (JRN-xxx), shell applicatif, thème visuel Material 3, catalogue des routes (UxRouteNode) et écrans (SCR-xxx).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'personaId': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant de persona.',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'inspect_ux_screen',
      description: 'Inspecte le détail complet d’un écran UX (UxScreenSpec) ou d’un parcours utilisateur (UxJourneySpec) par identifiant, code (SCR-001 / JRN-001), routeId ou nom.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'idOrCode': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, code (SCR-001 / JRN-001), routeId ou nom de l’écran ou du parcours UX à inspecter.',
          },
          'screenId': <String, Object?>{
            'type': 'string',
            'description':
                'Alias optionnel de idOrCode pour cibler un écran UX.',
          },
          'journeyId': <String, Object?>{
            'type': 'string',
            'description':
                'Alias optionnel de idOrCode pour cibler un parcours UX.',
          },
          'routeId': <String, Object?>{
            'type': 'string',
            'description': 'Alias optionnel de idOrCode pour cibler l’écran associé à une route.',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'run_ux_coherence_audit',
      description: 'Exécute le contrôle de cohérence et de traçabilité Métier↔UX (parcours, routes, écrans, attributs métiers et règles RG-xxx).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par étape UX (userJourneys, iaNavigation, screenBlueprints, uxReviewExport).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'focus_ux_item',
      description: 'Bascule l’atelier UX sur une étape donnée et sélectionne éventuellement un parcours (journeyId), une route (routeId), un écran (screenId) et/ou une zone cardinale (zone).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Étape UX cible (userJourneys, iaNavigation, screenBlueprints, uxReviewExport).',
          },
          'journeyId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code JRN-xxx du parcours à sélectionner (optionnel).',
          },
          'routeId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou chemin "/..." de la route à sélectionner (optionnel).',
          },
          'screenId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, code SCR-xxx ou routeId de l’écran à sélectionner (optionnel).',
          },
          'zone': <String, Object?>{
            'type': 'string',
            'description': 'Zone cardinale de l’écran à sélectionner (north, west, center, east, south).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_qa_overview',
      description: 'Retourne un aperçu synthétique du volet QA BDD/TDD : langue Gherkin active (fr / en), jeux d’essais (FIX-xxx), features et scénarios Gherkin (FEAT-xxx / SCN-xxx), et suites/cas TDD (TDD-xxx / TC-xxx).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par identifiant ou nom technique d’objet métier cible.',
          },
          'moduleId': <String, Object?>{
            'type': 'string',
            'description':
                'Filtre optionnel par identifiant de module fonctionnel.',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'inspect_qa_artifact',
      description: 'Inspecte le détail complet d’une fixture QA (QaFixtureSpec), d’une feature ou d’un scénario Gherkin (GherkinFeatureSpec / GherkinScenarioSpec), ou d’une suite TDD (TddTestSuiteSpec) par identifiant, code (FIX-001, FEAT-001, SCN-001, TDD-001) ou nom/titre.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'idOrCode': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, code (FIX-001, FEAT-001, SCN-001, TDD-001, TC-001) ou nom/titre de l’artefact QA à inspecter.',
          },
          'fixtureId': <String, Object?>{
            'type': 'string',
            'description':
                'Alias optionnel de idOrCode pour cibler une fixture QA.',
          },
          'featureId': <String, Object?>{
            'type': 'string',
            'description':
                'Alias optionnel de idOrCode pour cibler une feature Gherkin.',
          },
          'scenarioId': <String, Object?>{
            'type': 'string',
            'description':
                'Alias optionnel de idOrCode pour cibler un scénario Gherkin.',
          },
          'tddSuiteId': <String, Object?>{
            'type': 'string',
            'description':
                'Alias optionnel de idOrCode pour cibler une suite TDD.',
          },
          'kind': <String, Object?>{
            'type': 'string',
            'description': 'Indice optionnel de type d’artefact (fixture, feature, scenario, tddSuite).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'run_qa_coherence_audit',
      description: 'Exécute le contrôle de couverture 360° et de cohérence Métier+UX↔QA (couverture EXF/RG, variables <var> des plans de scénarios Gherkin, erreurs attendues TDD et références croisées).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel par étape QA (testFixtures, gherkinFeatures, tddSuites, qaReviewExport).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'focus_qa_item',
      description: 'Bascule l’atelier QA sur une étape donnée et sélectionne éventuellement une fixture (fixtureId), une feature Gherkin (featureId), un scénario (scenarioId) et/ou une suite TDD (tddSuiteId).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Étape QA cible (testFixtures, gherkinFeatures, tddSuites, qaReviewExport).',
          },
          'fixtureId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code FIX-xxx de la fixture à sélectionner (optionnel).',
          },
          'featureId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code FEAT-xxx de la feature Gherkin à sélectionner (optionnel).',
          },
          'scenarioId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code SCN-xxx du scénario Gherkin à sélectionner (optionnel).',
          },
          'tddSuiteId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code TDD-xxx de la suite TDD à sélectionner (optionnel).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'get_cost_overview',
      description: 'Retourne la synthèse complète du volet FinOps & Chiffrage : hypothèses TJM, totaux Build WBS CAPEX (MVP / V1 / Cible, PERT espéré & P80, Classique vs IA), coûts Run OPEX (mensuel, années 1..3, cumul 3/5 ans), provision risques EMV, TCO 1/3/5 ans et diagnostics de cohérence.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'priority': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel des lots WBS listés par priorité MoSCoW (must, should, could, wont).',
          },
          'discipline': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel des lots WBS par discipline (backend, frontendUx, dataModel, integration, qaTesting, devSecOps, projectManagement).',
          },
          'category': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel des postes Run par catégorie OPEX (cloudInfra, databaseStorage, thirdPartyApi, aiTokensLlm, saasLicenses, supportTma, securityCompliance).',
          },
          'moduleId': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel des lots WBS par identifiant de module fonctionnel.',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'inspect_cost_item',
      description: 'Inspecte le détail complet et les métriques calculées d’un profil TJM (CostProfileRate), d’un lot Build WBS (CostWbsItemSpec), d’un poste Run OPEX (CostRunItemSpec) ou d’un risque budgétaire (CostRiskItemSpec) par identifiant, code (PRF-xxx, WBS-001, RUN-001, RSK-001) ou nom/titre.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'idOrCode': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, code (PRF-xxx, WBS-001, RUN-001, RSK-001) ou nom/titre de l’élément FinOps à inspecter.',
          },
          'profileId': <String, Object?>{
            'type': 'string',
            'description': 'Alias optionnel de idOrCode pour cibler un profil TJM.',
          },
          'wbsItemId': <String, Object?>{
            'type': 'string',
            'description': 'Alias optionnel de idOrCode pour cibler un lot Build WBS.',
          },
          'runItemId': <String, Object?>{
            'type': 'string',
            'description': 'Alias optionnel de idOrCode pour cibler un poste Run OPEX.',
          },
          'riskItemId': <String, Object?>{
            'type': 'string',
            'description': 'Alias optionnel de idOrCode pour cibler un risque budgétaire.',
          },
          'kind': <String, Object?>{
            'type': 'string',
            'description': 'Indice optionnel du type d’élément (profile, wbs, run, risk).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'focus_cost_item',
      description: 'Bascule l’atelier FinOps & Chiffrage sur une étape donnée et sélectionne éventuellement un profil TJM (profileId), un lot WBS (wbsItemId), un poste Run OPEX (runItemId) ou un risque budgétaire (riskItemId).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Étape Coûts cible (rateCardAssumptions, buildWbs, runOpex, tcoReviewExport).',
          },
          'idOrCode': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code générique (PRF-xxx, WBS-xxx, RUN-xxx, RSK-xxx) de l’élément à sélectionner (optionnel).',
          },
          'profileId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code PRF-xxx du profil TJM à sélectionner (optionnel).',
          },
          'wbsItemId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code WBS-xxx du lot Build WBS à sélectionner (optionnel).',
          },
          'runItemId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code RUN-xxx du poste Run OPEX à sélectionner (optionnel).',
          },
          'riskItemId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou code RSK-xxx du risque budgétaire à sélectionner (optionnel).',
          },
        },
      },
    ),
  ];

  /// Crée un [VibeAppToolRegistry] complet incluant par défaut les outils Spec, UX et QA.
  static VibeAppToolRegistry create({
    required SpecForgeProject? Function() readProject,
    Future<void> Function(SpecForgeProject updated)? onUpdateProject,
    Future<void> Function(SpecForgeStage stage)? onNavigateStage,
    void Function(String? objectId)? onFocusObject,
    void Function({String? objectId, List<String> attributePath})?
    onFocusSelection,
    void Function(String? flowId)? onFocusEventStormFlow,
    void Function(String? storyId)? onFocusExampleStory,
    void Function(String query)? onFilterBusinessObjects,
    CompanyGlossary Function()? readCompanyGlossary,
    BusinessObjectModelPreferences Function()? readModelPreferences,
    List<UxCoherenceIssue> Function(SpecForgeProject project)?
    onRunUxCoherenceAudit,
    void Function({
      UxForgeStage? stage,
      String? journeyId,
      String? routeId,
      String? screenId,
      UxLayoutZoneName? zone,
    })?
    onFocusUxItem,
    List<QaCoherenceIssue> Function(SpecForgeProject project)?
    onRunQaCoherenceAudit,
    void Function({
      QaForgeStage? stage,
      String? fixtureId,
      String? featureId,
      String? scenarioId,
      String? tddSuiteId,
    })?
    onFocusQaItem,
    List<CostCoherenceIssue> Function(SpecForgeProject project)?
    onRunCostCoherenceAudit,
    void Function({
      CostForgeStage? stage,
      String? profileId,
      String? wbsItemId,
      String? runItemId,
      String? riskItemId,
    })?
    onFocusCostItem,
    Set<String>? toolNames,
    bool includeUxTools = true,
    bool includeQaTools = true,
    bool includeCostTools = true,
    bool Function(SpecCoherenceIssue issue)? coherenceIssueFilter,
  }) => build(
    readProject: readProject,
    onUpdateProject: onUpdateProject,
    onNavigateStage: onNavigateStage,
    onFocusObject: onFocusObject,
    onFocusSelection: onFocusSelection,
    onFocusEventStormFlow: onFocusEventStormFlow,
    onFocusExampleStory: onFocusExampleStory,
    onFilterBusinessObjects: onFilterBusinessObjects,
    readCompanyGlossary: readCompanyGlossary,
    readModelPreferences: readModelPreferences,
    onRunUxCoherenceAudit: onRunUxCoherenceAudit,
    onFocusUxItem: onFocusUxItem,
    onRunQaCoherenceAudit: onRunQaCoherenceAudit,
    onFocusQaItem: onFocusQaItem,
    onRunCostCoherenceAudit: onRunCostCoherenceAudit,
    onFocusCostItem: onFocusCostItem,
    toolNames: toolNames,
    includeUxTools: includeUxTools,
    includeQaTools: includeQaTools,
    includeCostTools: includeCostTools,
    coherenceIssueFilter: coherenceIssueFilter,
  );

  /// Construit un [VibeAppToolRegistry] connecté au projet courant et aux callbacks de mutation/navigation.
  ///
  /// [toolNames] restreint les outils enregistrés ; lorsqu'il est omis, les
  /// outils UX, QA et/ou Coûts sont activés dès que [includeUxTools],
  /// [includeQaTools] ou [includeCostTools] vaut `true` ou qu'un callback
  /// correspondant est fourni.
  static VibeAppToolRegistry build({
    required SpecForgeProject? Function() readProject,
    Future<void> Function(SpecForgeProject updated)? onUpdateProject,
    Future<void> Function(SpecForgeStage stage)? onNavigateStage,
    void Function(String? objectId)? onFocusObject,
    void Function({String? objectId, List<String> attributePath})?
    onFocusSelection,
    void Function(String? flowId)? onFocusEventStormFlow,
    void Function(String? storyId)? onFocusExampleStory,
    void Function(String query)? onFilterBusinessObjects,
    CompanyGlossary Function()? readCompanyGlossary,
    BusinessObjectModelPreferences Function()? readModelPreferences,
    List<UxCoherenceIssue> Function(SpecForgeProject project)?
    onRunUxCoherenceAudit,
    void Function({
      UxForgeStage? stage,
      String? journeyId,
      String? routeId,
      String? screenId,
      UxLayoutZoneName? zone,
    })?
    onFocusUxItem,
    List<QaCoherenceIssue> Function(SpecForgeProject project)?
    onRunQaCoherenceAudit,
    void Function({
      QaForgeStage? stage,
      String? fixtureId,
      String? featureId,
      String? scenarioId,
      String? tddSuiteId,
    })?
    onFocusQaItem,
    List<CostCoherenceIssue> Function(SpecForgeProject project)?
    onRunCostCoherenceAudit,
    void Function({
      CostForgeStage? stage,
      String? profileId,
      String? wbsItemId,
      String? runItemId,
      String? riskItemId,
    })?
    onFocusCostItem,
    Set<String>? toolNames,
    bool? includeUxTools,
    bool? includeQaTools,
    bool? includeCostTools,
    bool Function(SpecCoherenceIssue issue)? coherenceIssueFilter,
  }) {
    final handlers = <String, VibeToolHandler>{
      'get_lexicon_and_synonyms': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final q =
            (call.arguments['query'] as String?)?.trim().toLowerCase() ?? '';
        final terms = q.isEmpty
            ? project.lexicon.terms
            : project.lexicon.terms.where((t) {
                return t.term.toLowerCase().contains(q) ||
                    t.definition.toLowerCase().contains(q) ||
                    t.synonyms.any((s) => s.toLowerCase().contains(q));
              }).toList();
        final companyGlossary = readCompanyGlossary?.call();
        final companyTerms = companyGlossary == null
            ? const <CompanyGlossaryTerm>[]
            : (q.isEmpty
                  ? companyGlossary.terms
                  : companyGlossary.terms
                        .where((t) => t.matchesQuery(q))
                        .toList());
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'termCount': terms.length,
            'terms': [
              for (final t in terms)
                () {
                  final match = companyGlossary?.matchLexiconTerm(t);
                  return <String, Object?>{
                    ...t.toJson(),
                    'existsInCompanyGlossary': match != null,
                    if (match != null)
                      'companyGlossaryMatch': <String, Object?>{
                        'kind': match.kind.name,
                        'id': match.term.id,
                        'term': match.term.term,
                        'status': match.term.status.name,
                      },
                  };
                }(),
            ],
            'ambiguousTerms': project.lexicon.ambiguousTerms,
            'conventions': project.lexicon.conventions,
            if (companyGlossary != null && companyGlossary.hasContent)
              'companyGlossary': <String, Object?>{
                'termCount': companyTerms.length,
                'terms': [for (final t in companyTerms) t.toJson()],
                'conventions': companyGlossary.conventions,
                'ambiguousTerms': companyGlossary.ambiguousTerms,
              },
          },
        );
      },
      'get_requirements_summary': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final moduleFilter =
            (call.arguments['moduleId'] as String?)?.trim() ?? '';
        final priorityRaw =
            (call.arguments['priority'] as String?)?.trim() ?? '';
        final priorityFilter = priorityRaw.isEmpty
            ? null
            : RequirementPriority.fromJson(priorityRaw);
        final reqs = project.cahierDesCharges.functionalRequirements.where((r) {
          if (moduleFilter.isNotEmpty && r.moduleId != moduleFilter) {
            return false;
          }
          if (priorityFilter != null && r.priority != priorityFilter) {
            return false;
          }
          return true;
        }).toList();

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'moduleCount': project.cahierDesCharges.modules.length,
            'modules': [
              for (final m in project.cahierDesCharges.modules) m.toJson(),
            ],
            'functionalRequirementCount': reqs.length,
            'functionalRequirements': [for (final r in reqs) r.toJson()],
            'useCaseCount': project.cahierDesCharges.useCases.length,
            'useCases': [
              for (final u in project.cahierDesCharges.useCases) u.toJson(),
            ],
            'nfrCount':
                project.cahierDesCharges.nonFunctionalRequirements.length,
            'nonFunctionalRequirements': [
              for (final n
                  in project.cahierDesCharges.nonFunctionalRequirements)
                n.toJson(),
            ],
          },
        );
      },
      'get_event_storming': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final es = project.eventStorming;
        final docQuery =
            ((call.arguments['documentIdOrContext'] ??
                        call.arguments['boundedContextId'] ??
                        call.arguments['flowIdOrCode'])
                    as String?)
                ?.trim()
                .toLowerCase() ??
            '';
        final onlyOpenHotspots = call.arguments['onlyOpenHotspots'] == true;
        final includeYaml = call.arguments['includeYaml'] == true;

        final docs = es.documents.where((d) {
          if (docQuery.isNotEmpty &&
              d.id.toLowerCase() != docQuery &&
              d.fileName.toLowerCase() != docQuery &&
              !d.meta.boundedContext.toLowerCase().contains(docQuery)) {
            return false;
          }
          if (onlyOpenHotspots && d.openHotspotCount == 0) {
            return false;
          }
          return true;
        }).toList();

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'dslVersion': EventStormDocument.currentDslVersion,
            'documentCount': docs.length,
            'totalStepCount': es.totalStepCount,
            'totalEventCount': es.totalEventCount,
            'openHotspotCount': es.openHotspotCount,
            'documents': [
              for (final d in docs)
                <String, Object?>{
                  'id': d.id,
                  'fileName': d.fileName,
                  ...d.toDslJson(),
                  if (includeYaml) 'yaml': EventStormingDslCodec.toYaml(d),
                },
            ],
          },
        );
      },
      'inspect_business_object': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final targetKey =
            (call.arguments['objectIdOrName'] as String?)?.trim() ?? '';
        final includeYaml = call.arguments['includeYaml'] == true;
        if (targetKey.isEmpty) {
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'objectCount': project.businessObjects.length,
              'objects': [
                for (final o in project.businessObjects)
                  <String, Object?>{
                    'id': o.id,
                    'name': o.name,
                    'technicalName': o.technicalName,
                    'totalAttributeCount': o.totalAttributeCount,
                    'maxAttributes': BusinessObjectSpec.maxAttributesPerObject,
                    'relationCount': o.relations.length,
                  },
              ],
              if (includeYaml)
                'yamlLight': SpecSchemaDslBridge.toYamlLight(project),
            },
          );
        }
        final found = project.findBusinessObject(targetKey);
        if (found == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Objet métier introuvable : $targetKey',
          );
        }
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'object': found.toJson(),
            'totalAttributeCount': found.totalAttributeCount,
            'maxAttributes': BusinessObjectSpec.maxAttributesPerObject,
            if (includeYaml)
              'yamlLight': SpecSchemaDslBridge.toYamlLight(
                project.copyWith(businessObjects: [found]),
              ),
          },
        );
      },
      'get_example_mapping': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final objKey = (call.arguments['objectId'] as String?)?.trim() ?? '';
        final resolvedObj = objKey.isEmpty
            ? null
            : project.findBusinessObject(objKey);
        final storyKey =
            (call.arguments['storyIdOrCode'] as String?)?.trim().toLowerCase() ??
            '';
        final onlyOpenQuestions = call.arguments['onlyOpenQuestions'] == true;

        final stories = project.exampleMappings.where((s) {
          if (objKey.isNotEmpty) {
            final directMatch =
                s.targetObjectId == objKey ||
                (resolvedObj != null && s.targetObjectId == resolvedObj.id) ||
                s.rules.any(
                  (r) =>
                      r.targetObjectIds.contains(objKey) ||
                      (resolvedObj != null &&
                          r.targetObjectIds.contains(resolvedObj.id)),
                );
            if (!directMatch) return false;
          }
          if (storyKey.isNotEmpty &&
              s.id.toLowerCase() != storyKey &&
              s.code.toLowerCase() != storyKey &&
              !s.title.toLowerCase().contains(storyKey)) {
            return false;
          }
          if (onlyOpenQuestions && s.openQuestionCount == 0) {
            return false;
          }
          return true;
        }).toList();

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'storyCount': stories.length,
            'openQuestionCount': stories.fold<int>(
              0,
              (sum, s) => sum + s.openQuestionCount,
            ),
            'exampleCount': stories.fold<int>(
              0,
              (sum, s) => sum + s.totalExampleCount,
            ),
            'stories': [for (final s in stories) s.toJson()],
          },
        );
      },
      'get_business_rules': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final objKey = (call.arguments['objectId'] as String?)?.trim() ?? '';
        final resolvedObj = objKey.isEmpty
            ? null
            : project.findBusinessObject(objKey);
        final catRaw = (call.arguments['category'] as String?)?.trim() ?? '';
        final catFilter = catRaw.isEmpty
            ? null
            : BusinessRuleCategory.fromJson(catRaw);

        final rules = project.businessRules.where((r) {
          if (objKey.isNotEmpty) {
            final targetMatch =
                r.targetObjectIds.contains(objKey) ||
                (resolvedObj != null &&
                    r.targetObjectIds.contains(resolvedObj.id));
            if (!targetMatch) return false;
          }
          if (catFilter != null && r.category != catFilter) return false;
          return true;
        }).toList();

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'ruleCount': rules.length,
            'rules': [for (final r in rules) r.toJson()],
          },
        );
      },
      'get_debug_entries': (call) async {
        final rawType =
            (call.arguments['type'] as String?)?.trim().toLowerCase() ??
            'error';
        final DebugEntryType? typeFilter = switch (rawType) {
          'error' || 'errors' => DebugEntryType.error,
          'log' || 'logs' => DebugEntryType.log,
          _ => null,
        };
        final query =
            (call.arguments['query'] as String?)?.trim().toLowerCase() ?? '';
        final rawLimit = call.arguments['limit'];
        final limit = (rawLimit is num ? rawLimit.toInt() : 20).clamp(1, 50);

        final filtered = debugEntries.where((entry) {
          if (typeFilter != null && entry.type != typeFilter) return false;
          if (query.isNotEmpty &&
              !entry.message.toLowerCase().contains(query) &&
              !(entry.stackTrace?.toLowerCase().contains(query) ?? false)) {
            return false;
          }
          return true;
        }).toList();
        final recent = filtered.reversed.take(limit).toList();
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'totalEntries': debugEntries.length,
            'returnedCount': recent.length,
            'entries': [
              for (final e in recent)
                <String, Object?>{
                  'timestamp': e.timestamp.toIso8601String(),
                  'type': e.type.name,
                  'message': e.message.length > 500
                      ? '${e.message.substring(0, 500)}…'
                      : e.message,
                  if (e.stackTrace != null) 'stackTrace': e.stackTrace,
                },
            ],
          },
        );
      },
      'run_coherence_audit': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final issues = [
          for (final issue in SpecCoherenceAnalyzer.analyze(
            project,
            companyGlossary: readCompanyGlossary?.call(),
            modelPreferences: readModelPreferences?.call(),
          ))
            if (coherenceIssueFilter?.call(issue) ?? true) issue,
        ];
        final errorCount = issues
            .where((i) => i.severity == CoherenceSeverity.error)
            .length;
        final warningCount = issues
            .where((i) => i.severity == CoherenceSeverity.warning)
            .length;
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'issueCount': issues.length,
            'errorCount': errorCount,
            'warningCount': warningCount,
            'issues': [for (final i in issues) i.toJson()],
          },
        );
      },
      'validate_yaml_light_schema': (call) async {
        final yaml = (call.arguments['yaml'] as String?) ?? '';
        if (yaml.trim().isEmpty) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Le paramètre "yaml" est requis.',
          );
        }
        try {
          final parsedNodes = Yaml2JsonSchemasParser().parse(yaml);
          final objects = SpecSchemaDslBridge.fromYamlLight(
            yaml,
            existing: readProject()?.businessObjects ?? const [],
          );
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'valid': true,
              'rootNodeCount': parsedNodes.length,
              'objectCount': objects.length,
              'objects': [
                for (final o in objects)
                  <String, Object?>{
                    'technicalName': o.technicalName,
                    'totalAttributeCount': o.totalAttributeCount,
                    'maxAttributes': BusinessObjectSpec.maxAttributesPerObject,
                  },
              ],
            },
          );
        } on FormatException catch (e) {
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            isError: true,
            data: <String, Object?>{'valid': false, 'error': e.message},
          );
        }
      },
      'extract_array_to_business_object': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final objKey = (call.arguments['objectId'] as String?)?.trim() ?? '';
        final attrName =
            (call.arguments['attributeName'] as String?)?.trim() ?? '';
        final parent = project.findBusinessObject(objKey);
        if (parent == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Objet métier introuvable : $objKey',
          );
        }
        final attr = parent.attributes
            .where((a) => a.name == attrName && a.isArray)
            .firstOrNull;
        if (attr == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message:
                'Attribut tableau "$attrName" introuvable sur ${parent.technicalName}.',
          );
        }
        final customName =
            (call.arguments['newObjectName'] as String?)?.trim() ?? '';
        final techName = customName.isNotEmpty
            ? _toPascal(customName)
            : _singularizePascal(attr.name);
        final newId = 'obj_${shortid.generate()}';
        final newAttributes = attr.children.isNotEmpty
            ? [
                ...attr.children,
                BusinessAttribute(
                  id: 'attr_${shortid.generate()}',
                  name: '${_toCamel(parent.technicalName)}Id',
                  type: BusinessAttributeType.reference,
                  required: true,
                  referenceObjectId: parent.id,
                ),
              ]
            : [
                BusinessAttribute(
                  id: 'attr_${shortid.generate()}',
                  name: 'libelle',
                  type: BusinessAttributeType.string,
                  required: true,
                ),
                BusinessAttribute(
                  id: 'attr_${shortid.generate()}',
                  name: '${_toCamel(parent.technicalName)}Id',
                  type: BusinessAttributeType.reference,
                  required: true,
                  referenceObjectId: parent.id,
                ),
              ];
        final newObj = BusinessObjectSpec(
          id: newId,
          name: techName,
          technicalName: techName,
          description:
              'Objet métier dédié extrait du tableau ${parent.technicalName}.${attr.name}.',
          attributes: newAttributes,
        );
        final updatedParent = parent.copyWith(
          attributes: parent.attributes.where((a) => a.id != attr.id).toList(),
          relations: [
            ...parent.relations,
            BusinessRelation(
              id: 'rel_${shortid.generate()}',
              name: attr.name,
              targetObjectId: newId,
              cardinality: BusinessRelationCardinality.oneToMany,
              required: attr.required,
              description: attr.description,
            ),
          ],
        );
        final nextObjects = [
          for (final o in project.businessObjects)
            if (o.id == updatedParent.id) updatedParent else o,
          newObj,
        ];
        if (onUpdateProject != null) {
          await onUpdateProject(project.copyWith(businessObjects: nextObjects));
        }
        onFocusObject?.call(newId);
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'extractedObjectId': newId,
            'technicalName': techName,
            'relationOnParent': '${parent.technicalName}.${attr.name}',
          },
        );
      },
      'focus_stage_or_object': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final stageName = (call.arguments['stage'] as String?)?.trim() ?? '';
        final stage = stageName.isEmpty
            ? project.currentStage
            : SpecForgeStage.fromJson(stageName);
        if (onNavigateStage != null) {
          await onNavigateStage(stage);
        }
        final objKey = (call.arguments['objectId'] as String?)?.trim() ?? '';
        final attrQuery =
            (call.arguments['attributePath'] as String?)?.trim() ?? '';
        String? resolvedId;
        BusinessObjectSpec? targetObj;
        if (objKey.isNotEmpty) {
          targetObj = project.findBusinessObject(objKey);
          if (targetObj == null) {
            return VibeToolResult.error(
              callId: call.id,
              name: call.name,
              message: 'Objet métier introuvable : $objKey',
            );
          }
          resolvedId = targetObj.id;
        }
        var resolvedAttrPath = const <String>[];
        String? resolvedAttrDotPath;
        if (attrQuery.isNotEmpty) {
          if (targetObj != null) {
            final match = _resolveAttributePath(
              targetObj.attributes,
              attrQuery,
            );
            if (match == null) {
              return VibeToolResult.error(
                callId: call.id,
                name: call.name,
                message:
                    'Attribut "$attrQuery" introuvable sur ${targetObj.technicalName}.',
              );
            }
            resolvedAttrPath = match.ids;
            resolvedAttrDotPath =
                '${targetObj.technicalName}.${match.names.join('.')}';
          } else {
            for (final candidate in project.businessObjects) {
              final match = _resolveAttributePath(
                candidate.attributes,
                attrQuery,
              );
              if (match != null) {
                targetObj = candidate;
                resolvedId = candidate.id;
                resolvedAttrPath = match.ids;
                resolvedAttrDotPath =
                    '${candidate.technicalName}.${match.names.join('.')}';
                break;
              }
            }
            if (resolvedAttrPath.isEmpty) {
              return VibeToolResult.error(
                callId: call.id,
                name: call.name,
                message: 'Attribut "$attrQuery" introuvable dans le modèle.',
              );
            }
          }
        }
        final flowQuery =
            (call.arguments['eventStormFlowId'] as String?)?.trim() ?? '';
        String? resolvedFlowId;
        if (flowQuery.isNotEmpty) {
          final foundDoc = project.eventStorming.findDocument(flowQuery);
          if (foundDoc == null) {
            return VibeToolResult.error(
              callId: call.id,
              name: call.name,
              message: 'Document Event Storming introuvable : $flowQuery',
            );
          }
          resolvedFlowId = foundDoc.id;
          onFocusEventStormFlow?.call(resolvedFlowId);
        }
        final storyQuery =
            (call.arguments['exampleStoryId'] as String?)?.trim() ?? '';
        String? resolvedStoryId;
        if (storyQuery.isNotEmpty) {
          final needle = storyQuery.toLowerCase();
          final foundStory = project.exampleMappings
              .where(
                (s) =>
                    s.id.toLowerCase() == needle ||
                    s.code.toLowerCase() == needle,
              )
              .firstOrNull;
          if (foundStory == null) {
            return VibeToolResult.error(
              callId: call.id,
              name: call.name,
              message: 'Tableau Example Mapping introuvable : $storyQuery',
            );
          }
          resolvedStoryId = foundStory.id;
          onFocusExampleStory?.call(resolvedStoryId);
        }
        if (resolvedId != null) {
          if (onFocusSelection != null) {
            onFocusSelection(
              objectId: resolvedId,
              attributePath: resolvedAttrPath,
            );
          } else {
            onFocusObject?.call(resolvedId);
          }
        }
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'stage': stage.name,
            'focusedObjectId': ?resolvedId,
            'focusedEventStormFlowId': ?resolvedFlowId,
            'focusedExampleStoryId': ?resolvedStoryId,
            if (resolvedAttrPath.isNotEmpty)
              'focusedAttributePath': resolvedAttrPath,
            'focusedAttribute': ?resolvedAttrDotPath,
          },
        );
      },
      'filter_business_objects': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final query = (call.arguments['query'] as String?)?.trim() ?? '';
        onFilterBusinessObjects?.call(query);
        final lower = query.toLowerCase();
        var matchingObjects = 0;
        var matchingAttributes = 0;
        for (final obj in project.businessObjects) {
          final objMatches =
              lower.isEmpty ||
              obj.name.toLowerCase().contains(lower) ||
              obj.technicalName.toLowerCase().contains(lower) ||
              obj.description.toLowerCase().contains(lower);
          final attrHits = _countMatchingAttributes(obj.attributes, lower);
          if (objMatches || attrHits > 0) {
            matchingObjects++;
            matchingAttributes += attrHits;
          }
        }
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'query': query,
            'matchingObjectCount': matchingObjects,
            'matchingAttributeCount': matchingAttributes,
          },
        );
      },
      'get_ux_overview': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final ux = project.uxSpec;
        final personaFilter =
            (call.arguments['personaId'] as String?)?.trim() ?? '';
        final journeys = personaFilter.isEmpty
            ? ux.journeys
            : ux.journeys.where((j) => j.personaId == personaFilter).toList();
        final routes = personaFilter.isEmpty
            ? ux.navigation.routes
            : ux.navigation.routes
                  .where(
                    (r) =>
                        r.allowedPersonaIds.isEmpty ||
                        r.allowedPersonaIds.contains(personaFilter),
                  )
                  .toList();
        final screens = personaFilter.isEmpty
            ? ux.screens
            : ux.screens
                  .where(
                    (s) =>
                        s.personaIds.isEmpty ||
                        s.personaIds.contains(personaFilter),
                  )
                  .toList();
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'currentUxStage': ux.currentStage.name,
            'hasContent': ux.hasContent,
            'journeyCount': journeys.length,
            'journeys': [
              for (final j in journeys)
                <String, Object?>{
                  'id': j.id,
                  'code': j.code,
                  'name': j.name,
                  'personaId': j.personaId,
                  'channel': j.channel.name,
                  'stepCount': j.steps.length,
                  'useCaseIds': j.useCaseIds,
                  'requirementIds': j.requirementIds,
                },
            ],
            'shell': <String, Object?>{
              'shellPattern': ux.navigation.shellPattern.name,
              'hasAppBar': ux.navigation.hasAppBar,
              'hasBreadcrumbs': ux.navigation.hasBreadcrumbs,
              'hasGlobalSearch': ux.navigation.hasGlobalSearch,
              'homeRouteId': ux.navigation.homeRouteId,
            },
            'visualTheme': ux.navigation.visualTheme.toJson(),
            'routeCount': routes.length,
            'routes': [for (final r in routes) r.toJson()],
            'screenCount': screens.length,
            'screens': [
              for (final s in screens)
                <String, Object?>{
                  'id': s.id,
                  'code': s.code,
                  'name': s.name,
                  'routeId': s.routeId,
                  'pattern': s.pattern.name,
                  'primaryObjectId': s.primaryObjectId,
                  'zoneCount': s.zones.length,
                  'actionCount': s.actions.length,
                },
            ],
            'coherenceIssueCount': ux.coherenceIssues.length,
          },
        );
      },
      'inspect_ux_screen': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final ux = project.uxSpec;
        String readArg(List<String> keys) {
          for (final key in keys) {
            final v = call.arguments[key];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return '';
        }

        final needle = readArg(const <String>[
          'idOrCode',
          'screenId',
          'journeyId',
          'routeId',
          'target',
          'id',
          'code',
          'name',
        ]);

        if (needle.isEmpty) {
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'screenCount': ux.screens.length,
              'journeyCount': ux.journeys.length,
              'screens': [
                for (final s in ux.screens)
                  <String, Object?>{
                    'id': s.id,
                    'code': s.code,
                    'name': s.name,
                    'routeId': s.routeId,
                    'pattern': s.pattern.name,
                  },
              ],
              'journeys': [
                for (final j in ux.journeys)
                  <String, Object?>{
                    'id': j.id,
                    'code': j.code,
                    'name': j.name,
                    'personaId': j.personaId,
                  },
              ],
            },
          );
        }

        final preferJourney =
            call.arguments['journeyId'] is String &&
            (call.arguments['journeyId'] as String).trim().isNotEmpty;

        if (preferJourney) {
          final journey = ux.findJourney(needle);
          if (journey != null) {
            return VibeToolResult(
              callId: call.id,
              name: call.name,
              data: <String, Object?>{
                'kind': 'journey',
                'journey': journey.toJson(),
              },
            );
          }
        }

        var screen = ux.findScreen(needle);
        if (screen == null) {
          final matchedRoute = ux.navigation.findRoute(needle);
          if (matchedRoute != null) {
            screen = ux.findScreen(matchedRoute.id);
          }
        }
        if (screen != null) {
          final linkedRoute = screen.routeId.isNotEmpty
              ? ux.navigation.findRoute(screen.routeId)
              : null;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'screen',
              'screen': screen.toJson(),
              if (linkedRoute != null) 'route': linkedRoute.toJson(),
            },
          );
        }

        final journey = ux.findJourney(needle);
        if (journey != null) {
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'journey',
              'journey': journey.toJson(),
            },
          );
        }

        return VibeToolResult.error(
          callId: call.id,
          name: call.name,
          message: 'Écran ou parcours UX introuvable : $needle',
        );
      },
      'run_ux_coherence_audit': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final allIssues = onRunUxCoherenceAudit != null
            ? onRunUxCoherenceAudit(project)
            : project.uxSpec.coherenceIssues;
        final stageRaw = (call.arguments['stage'] as String?)?.trim() ?? '';
        final stageFilter = stageRaw.isEmpty
            ? null
            : UxForgeStage.fromJson(stageRaw);
        final issues = stageFilter == null
            ? allIssues
            : allIssues.where((i) => i.stage == stageFilter).toList();
        final errorCount = issues
            .where((i) => i.severity == CoherenceSeverity.error)
            .length;
        final warningCount = issues
            .where((i) => i.severity == CoherenceSeverity.warning)
            .length;
        final infoCount = issues
            .where((i) => i.severity == CoherenceSeverity.info)
            .length;
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'issueCount': issues.length,
            'errorCount': errorCount,
            'warningCount': warningCount,
            'infoCount': infoCount,
            'issues': [for (final i in issues) i.toJson()],
          },
        );
      },
      'focus_ux_item': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final ux = project.uxSpec;
        final stageRaw = (call.arguments['stage'] as String?)?.trim() ?? '';
        final journeyRaw =
            (call.arguments['journeyId'] as String?)?.trim() ?? '';
        final routeRaw = (call.arguments['routeId'] as String?)?.trim() ?? '';
        final screenRaw = (call.arguments['screenId'] as String?)?.trim() ?? '';
        final zoneRaw = (call.arguments['zone'] as String?)?.trim() ?? '';

        UxForgeStage? resolvedStage = stageRaw.isEmpty
            ? null
            : UxForgeStage.fromJson(stageRaw);
        final resolvedJourneyId = journeyRaw.isEmpty
            ? null
            : (ux.findJourney(journeyRaw)?.id ?? journeyRaw);
        final resolvedRouteId = routeRaw.isEmpty
            ? null
            : (ux.navigation.findRoute(routeRaw)?.id ?? routeRaw);
        final resolvedScreenId = screenRaw.isEmpty
            ? null
            : (ux.findScreen(screenRaw)?.id ?? screenRaw);
        final UxLayoutZoneName? resolvedZone = zoneRaw.isEmpty
            ? null
            : UxLayoutZoneName.fromJson(zoneRaw);

        if (resolvedStage == null) {
          if (resolvedScreenId != null || resolvedZone != null) {
            resolvedStage = UxForgeStage.screenBlueprints;
          } else if (resolvedRouteId != null) {
            resolvedStage = UxForgeStage.iaNavigation;
          } else if (resolvedJourneyId != null) {
            resolvedStage = UxForgeStage.userJourneys;
          }
        }

        onFocusUxItem?.call(
          stage: resolvedStage,
          journeyId: resolvedJourneyId,
          routeId: resolvedRouteId,
          screenId: resolvedScreenId,
          zone: resolvedZone,
        );

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            if (resolvedStage != null) 'stage': resolvedStage.name,
            'focusedJourneyId': ?resolvedJourneyId,
            'focusedRouteId': ?resolvedRouteId,
            'focusedScreenId': ?resolvedScreenId,
            if (resolvedZone != null) 'focusedZone': resolvedZone.name,
          },
        );
      },
      'get_qa_overview': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final qa = project.qaSpec;
        final objFilter = (call.arguments['objectId'] as String?)?.trim() ?? '';
        final resolvedObj = objFilter.isEmpty
            ? null
            : project.findBusinessObject(objFilter);
        final moduleFilter =
            (call.arguments['moduleId'] as String?)?.trim() ?? '';

        bool matchesObject(String candidateObjectId) {
          if (objFilter.isEmpty) return true;
          final lower = candidateObjectId.toLowerCase();
          if (lower == objFilter.toLowerCase()) return true;
          if (resolvedObj != null) {
            return lower == resolvedObj.id.toLowerCase() ||
                lower == resolvedObj.technicalName.toLowerCase() ||
                lower == resolvedObj.name.toLowerCase();
          }
          return false;
        }

        final fixtures = objFilter.isEmpty
            ? qa.fixtures
            : qa.fixtures
                  .where((f) => matchesObject(f.businessObjectId))
                  .toList();
        final features = moduleFilter.isEmpty
            ? qa.features
            : qa.features
                  .where(
                    (f) =>
                        f.moduleId.toLowerCase() == moduleFilter.toLowerCase(),
                  )
                  .toList();
        final suites = qa.tddSuites.where((s) {
          if (objFilter.isNotEmpty && !matchesObject(s.targetObjectId)) {
            return false;
          }
          if (moduleFilter.isNotEmpty &&
              s.moduleId.toLowerCase() != moduleFilter.toLowerCase()) {
            return false;
          }
          return true;
        }).toList();

        final scenarioCount = features.fold<int>(
          0,
          (sum, f) => sum + f.scenarios.length,
        );
        final tddCaseCount = suites.fold<int>(
          0,
          (sum, s) => sum + s.cases.length,
        );

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'currentQaStage': qa.currentStage.name,
            'gherkinLanguage': qa.gherkinLanguage.name,
            'gherkinHeader': qa.gherkinLanguage.gherkinHeader,
            'hasContent': qa.hasContent,
            'fixtureCount': fixtures.length,
            'fixtures': [
              for (final f in fixtures)
                <String, Object?>{
                  'id': f.id,
                  'code': f.code,
                  'name': f.name,
                  'kind': f.kind.name,
                  'businessObjectId': f.businessObjectId,
                  'personaId': f.personaId,
                  'businessRuleIds': f.businessRuleIds,
                  'expectedValid': f.expectedValid,
                },
            ],
            'featureCount': features.length,
            'scenarioCount': scenarioCount,
            'features': [
              for (final f in features)
                <String, Object?>{
                  'id': f.id,
                  'code': f.code,
                  'title': f.title,
                  'moduleId': f.moduleId,
                  'personaId': f.personaId,
                  'tags': f.tags,
                  'backgroundStepCount': f.backgroundSteps.length,
                  'scenarioCount': f.scenarios.length,
                  'scenarios': [
                    for (final sc in f.scenarios)
                      <String, Object?>{
                        'id': sc.id,
                        'code': sc.code,
                        'title': sc.title,
                        'isOutline': sc.isOutline,
                        'tags': sc.tags,
                        'stepCount': sc.steps.length,
                        'requirementIds': sc.requirementIds,
                        'useCaseIds': sc.useCaseIds,
                        'businessRuleIds': sc.businessRuleIds,
                        'journeyIds': sc.journeyIds,
                        'screenIds': sc.screenIds,
                        'fixtureIds': sc.fixtureIds,
                      },
                  ],
                },
            ],
            'tddSuiteCount': suites.length,
            'tddCaseCount': tddCaseCount,
            'tddSuites': [
              for (final s in suites)
                <String, Object?>{
                  'id': s.id,
                  'code': s.code,
                  'name': s.name,
                  'layer': s.layer.name,
                  'targetObjectId': s.targetObjectId,
                  'moduleId': s.moduleId,
                  'caseCount': s.cases.length,
                  'cases': [
                    for (final c in s.cases)
                      <String, Object?>{
                        'id': c.id,
                        'code': c.code,
                        'order': c.order,
                        'title': c.title,
                        'fixtureId': c.fixtureId,
                        'outcomeKind': c.outcomeKind.name,
                        'businessRuleIds': c.businessRuleIds,
                        'requirementIds': c.requirementIds,
                        'screenIds': c.screenIds,
                      },
                  ],
                },
            ],
            'coherenceIssueCount': qa.coherenceIssues.length,
          },
        );
      },
      'inspect_qa_artifact': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final qa = project.qaSpec;
        String readArg(List<String> keys) {
          for (final key in keys) {
            final v = call.arguments[key];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return '';
        }

        final needle = readArg(const <String>[
          'idOrCode',
          'fixtureId',
          'featureId',
          'scenarioId',
          'tddSuiteId',
          'target',
          'id',
          'code',
          'name',
          'title',
        ]);

        if (needle.isEmpty) {
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'gherkinLanguage': qa.gherkinLanguage.name,
              'fixtureCount': qa.fixtures.length,
              'featureCount': qa.features.length,
              'scenarioCount': qa.totalScenarioCount,
              'tddSuiteCount': qa.tddSuites.length,
              'tddCaseCount': qa.totalTddCaseCount,
              'fixtures': [
                for (final f in qa.fixtures)
                  <String, Object?>{
                    'id': f.id,
                    'code': f.code,
                    'name': f.name,
                    'kind': f.kind.name,
                  },
              ],
              'features': [
                for (final f in qa.features)
                  <String, Object?>{
                    'id': f.id,
                    'code': f.code,
                    'title': f.title,
                    'scenarioCount': f.scenarios.length,
                  },
              ],
              'tddSuites': [
                for (final s in qa.tddSuites)
                  <String, Object?>{
                    'id': s.id,
                    'code': s.code,
                    'name': s.name,
                    'layer': s.layer.name,
                    'caseCount': s.cases.length,
                  },
              ],
            },
          );
        }

        final kindHint =
            (call.arguments['kind'] as String?)?.trim().toLowerCase() ?? '';
        final preferFixture =
            kindHint == 'fixture' ||
            (call.arguments['fixtureId'] is String &&
                (call.arguments['fixtureId'] as String).trim().isNotEmpty);
        final preferFeature =
            kindHint == 'feature' ||
            (call.arguments['featureId'] is String &&
                (call.arguments['featureId'] as String).trim().isNotEmpty);
        final preferScenario =
            kindHint == 'scenario' ||
            (call.arguments['scenarioId'] is String &&
                (call.arguments['scenarioId'] as String).trim().isNotEmpty);
        final preferSuite =
            kindHint == 'tddsuite' ||
            kindHint == 'tdd_suite' ||
            kindHint == 'suite' ||
            kindHint == 'tdd' ||
            (call.arguments['tddSuiteId'] is String &&
                (call.arguments['tddSuiteId'] as String).trim().isNotEmpty);

        VibeToolResult? tryFixture() {
          final fixture = qa.findFixture(needle);
          if (fixture == null) return null;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'fixture',
              'fixture': fixture.toJson(),
            },
          );
        }

        VibeToolResult? tryFeature() {
          final feature = qa.findFeature(needle);
          if (feature == null) return null;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'feature',
              'gherkinLanguage': qa.gherkinLanguage.name,
              'feature': feature.toJson(),
            },
          );
        }

        VibeToolResult? tryScenario() {
          final matched = _findScenarioInQa(qa, needle);
          if (matched == null) return null;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'scenario',
              'gherkinLanguage': qa.gherkinLanguage.name,
              'feature': matched.feature.toJson(),
              'scenario': matched.scenario.toJson(),
            },
          );
        }

        VibeToolResult? tryTddSuite() {
          final suite = qa.findTddSuite(needle);
          if (suite != null) {
            return VibeToolResult(
              callId: call.id,
              name: call.name,
              data: <String, Object?>{
                'kind': 'tddSuite',
                'tddSuite': suite.toJson(),
              },
            );
          }
          final matchedCase = _findTddCaseInQa(qa, needle);
          if (matchedCase != null) {
            return VibeToolResult(
              callId: call.id,
              name: call.name,
              data: <String, Object?>{
                'kind': 'tddSuite',
                'tddSuite': matchedCase.suite.toJson(),
                'matchedCase': matchedCase.testCase.toJson(),
              },
            );
          }
          return null;
        }

        final resolvers = <VibeToolResult? Function()>[
          if (preferFixture) tryFixture,
          if (preferFeature) tryFeature,
          if (preferScenario) tryScenario,
          if (preferSuite) tryTddSuite,
          tryFixture,
          tryFeature,
          tryScenario,
          tryTddSuite,
        ];

        for (final resolve in resolvers) {
          final found = resolve();
          if (found != null) return found;
        }

        return VibeToolResult.error(
          callId: call.id,
          name: call.name,
          message: 'Artefact QA introuvable : $needle',
        );
      },
      'run_qa_coherence_audit': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final allIssues = onRunQaCoherenceAudit != null
            ? onRunQaCoherenceAudit(project)
            : project.qaSpec.coherenceIssues;
        final stageRaw = (call.arguments['stage'] as String?)?.trim() ?? '';
        final stageFilter = stageRaw.isEmpty
            ? null
            : QaForgeStage.fromJson(stageRaw);
        final issues = stageFilter == null
            ? allIssues
            : allIssues.where((i) => i.stage == stageFilter).toList();
        final errorCount = issues
            .where((i) => i.severity == CoherenceSeverity.error)
            .length;
        final warningCount = issues
            .where((i) => i.severity == CoherenceSeverity.warning)
            .length;
        final infoCount = issues
            .where((i) => i.severity == CoherenceSeverity.info)
            .length;
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'issueCount': issues.length,
            'errorCount': errorCount,
            'warningCount': warningCount,
            'infoCount': infoCount,
            'issues': [for (final i in issues) i.toJson()],
          },
        );
      },
      'focus_qa_item': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final qa = project.qaSpec;
        final stageRaw = (call.arguments['stage'] as String?)?.trim() ?? '';
        final fixtureRaw =
            (call.arguments['fixtureId'] as String?)?.trim() ?? '';
        final featureRaw =
            (call.arguments['featureId'] as String?)?.trim() ?? '';
        final scenarioRaw =
            (call.arguments['scenarioId'] as String?)?.trim() ?? '';
        final tddSuiteRaw =
            (call.arguments['tddSuiteId'] as String?)?.trim() ?? '';

        QaForgeStage? resolvedStage = stageRaw.isEmpty
            ? null
            : QaForgeStage.fromJson(stageRaw);
        final resolvedFixtureId = fixtureRaw.isEmpty
            ? null
            : (qa.findFixture(fixtureRaw)?.id ?? fixtureRaw);
        var resolvedFeatureId = featureRaw.isEmpty
            ? null
            : (qa.findFeature(featureRaw)?.id ?? featureRaw);

        String? resolvedScenarioId;
        if (scenarioRaw.isNotEmpty) {
          final matched = _findScenarioInQa(qa, scenarioRaw);
          if (matched != null) {
            resolvedScenarioId = matched.scenario.id;
            resolvedFeatureId ??= matched.feature.id;
          } else {
            resolvedScenarioId = scenarioRaw;
          }
        }

        final resolvedTddSuiteId = tddSuiteRaw.isEmpty
            ? null
            : (qa.findTddSuite(tddSuiteRaw)?.id ??
                  _findTddCaseInQa(qa, tddSuiteRaw)?.suite.id ??
                  tddSuiteRaw);

        if (resolvedStage == null) {
          if (resolvedTddSuiteId != null) {
            resolvedStage = QaForgeStage.tddSuites;
          } else if (resolvedFeatureId != null || resolvedScenarioId != null) {
            resolvedStage = QaForgeStage.gherkinFeatures;
          } else if (resolvedFixtureId != null) {
            resolvedStage = QaForgeStage.testFixtures;
          }
        }

        onFocusQaItem?.call(
          stage: resolvedStage,
          fixtureId: resolvedFixtureId,
          featureId: resolvedFeatureId,
          scenarioId: resolvedScenarioId,
          tddSuiteId: resolvedTddSuiteId,
        );

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            if (resolvedStage != null) 'stage': resolvedStage.name,
            'focusedFixtureId': ?resolvedFixtureId,
            'focusedFeatureId': ?resolvedFeatureId,
            'focusedScenarioId': ?resolvedScenarioId,
            'focusedTddSuiteId': ?resolvedTddSuiteId,
          },
        );
      },
      'get_cost_overview': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final cost = project.costSpec;
        final priorityRaw =
            (call.arguments['priority'] as String?)?.trim() ?? '';
        final disciplineRaw =
            (call.arguments['discipline'] as String?)?.trim() ?? '';
        final categoryRaw =
            (call.arguments['category'] as String?)?.trim() ?? '';
        final moduleRaw =
            (call.arguments['moduleId'] as String?)?.trim() ?? '';

        final priorityFilter = priorityRaw.isEmpty
            ? null
            : RequirementPriority.fromJson(priorityRaw);
        final disciplineFilter = disciplineRaw.isEmpty
            ? null
            : CostDiscipline.fromJson(disciplineRaw);
        final categoryFilter = categoryRaw.isEmpty
            ? null
            : CostRunCategory.fromJson(categoryRaw);

        final filteredWbs = cost.wbsItems.where((w) {
          if (priorityFilter != null && w.priority != priorityFilter) {
            return false;
          }
          if (disciplineFilter != null && w.discipline != disciplineFilter) {
            return false;
          }
          if (moduleRaw.isNotEmpty && w.moduleId != moduleRaw) {
            return false;
          }
          return true;
        }).toList();

        final filteredRuns = cost.runItems.where((r) {
          if (categoryFilter != null && r.category != categoryFilter) {
            return false;
          }
          return true;
        }).toList();

        final issues = onRunCostCoherenceAudit != null
            ? onRunCostCoherenceAudit(project)
            : cost.coherenceIssues;
        final summary = buildCostSummaryJson(cost);

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'currentCostStage': cost.currentStage.name,
            'currency': cost.currency.code,
            'hoursPerDay': cost.hoursPerDay,
            'deliveryMode': cost.deliveryMode.name,
            'targetUsersCount': cost.targetUsersCount,
            'profileCount': cost.profiles.length,
            'wbsItemCount': filteredWbs.length,
            'totalWbsItemCount': cost.wbsItems.length,
            'runItemCount': filteredRuns.length,
            'totalRunItemCount': cost.runItems.length,
            'riskItemCount': cost.riskItems.length,
            'coherenceIssueCount': issues.length,
            'summary': summary,
            'transverseRatios': cost.transverseRatios.toJson(),
            'aiProductivity': cost.aiProductivity.toJson(),
            if (cost.assumptionsNotes.isNotEmpty)
              'assumptionsNotes': cost.assumptionsNotes,
            'profiles': [
              for (final p in cost.profiles)
                <String, Object?>{
                  'id': p.id,
                  'code': p.code,
                  'name': p.name,
                  'seniority': p.seniority,
                  'discipline': p.discipline.name,
                  'internalDailyRate': p.internalDailyRate,
                  'externalDailyRate': p.externalDailyRate,
                  'effectiveDailyRate': _round2(
                    p.effectiveDailyRate(cost.deliveryMode),
                  ),
                },
            ],
            'wbsItems': [
              for (final w in filteredWbs)
                <String, Object?>{
                  'id': w.id,
                  'code': w.code,
                  'title': w.title,
                  'discipline': w.discipline.name,
                  'priority': w.priority.name,
                  'profileId': w.profileId,
                  'tshirtSize': w.tshirtSize.name,
                  'expectedDays': _round2(w.expectedDays),
                  'aiEligible': w.aiEligible,
                  if (w.moduleId.isNotEmpty) 'moduleId': w.moduleId,
                },
            ],
            'runItems': [
              for (final r in filteredRuns)
                <String, Object?>{
                  'id': r.id,
                  'code': r.code,
                  'name': r.name,
                  'category': r.category.name,
                  'environment': r.environment.name,
                  'billingCycle': r.billingCycle.name,
                  'monthlyCost': _round2(r.monthlyCost),
                  'yearlyCost': _round2(r.yearlyCost),
                  'annualGrowthPct': r.annualGrowthPct,
                  'enabled': r.enabled,
                },
            ],
            'riskItems': [
              for (final r in cost.riskItems)
                <String, Object?>{
                  'id': r.id,
                  'code': r.code,
                  'title': r.title,
                  'probabilityPct': r.probabilityPct,
                  'expectedDays': _round2(r.expectedDays),
                  'expectedFixedCost': _round2(r.expectedFixedCost),
                  'profileId': r.profileId,
                  if (r.linkedHotspotId.isNotEmpty)
                    'linkedHotspotId': r.linkedHotspotId,
                },
            ],
            'coherenceIssues': [for (final i in issues) i.toJson()],
          },
        );
      },
      'inspect_cost_item': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final cost = project.costSpec;

        String readArg(List<String> keys) {
          for (final key in keys) {
            final v = call.arguments[key];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return '';
        }

        final needle = readArg(const <String>[
          'idOrCode',
          'wbsItemId',
          'runItemId',
          'riskItemId',
          'profileId',
          'target',
          'id',
          'code',
          'name',
          'title',
        ]);

        if (needle.isEmpty) {
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'currency': cost.currency.code,
              'profileCount': cost.profiles.length,
              'wbsItemCount': cost.wbsItems.length,
              'runItemCount': cost.runItems.length,
              'riskItemCount': cost.riskItems.length,
              'profiles': [
                for (final p in cost.profiles)
                  <String, Object?>{
                    'id': p.id,
                    'code': p.code,
                    'name': p.name,
                    'discipline': p.discipline.name,
                  },
              ],
              'wbsItems': [
                for (final w in cost.wbsItems)
                  <String, Object?>{
                    'id': w.id,
                    'code': w.code,
                    'title': w.title,
                    'priority': w.priority.name,
                  },
              ],
              'runItems': [
                for (final r in cost.runItems)
                  <String, Object?>{
                    'id': r.id,
                    'code': r.code,
                    'name': r.name,
                    'category': r.category.name,
                  },
              ],
              'riskItems': [
                for (final r in cost.riskItems)
                  <String, Object?>{
                    'id': r.id,
                    'code': r.code,
                    'title': r.title,
                  },
              ],
            },
          );
        }

        final kindHint =
            (call.arguments['kind'] as String?)?.trim().toLowerCase() ?? '';
        final preferProfile =
            kindHint == 'profile' ||
            kindHint == 'rate' ||
            (call.arguments['profileId'] is String &&
                (call.arguments['profileId'] as String).trim().isNotEmpty);
        final preferWbs =
            kindHint == 'wbs' ||
            kindHint == 'wbsitem' ||
            kindHint == 'build' ||
            (call.arguments['wbsItemId'] is String &&
                (call.arguments['wbsItemId'] as String).trim().isNotEmpty);
        final preferRun =
            kindHint == 'run' ||
            kindHint == 'runitem' ||
            kindHint == 'opex' ||
            (call.arguments['runItemId'] is String &&
                (call.arguments['runItemId'] as String).trim().isNotEmpty);
        final preferRisk =
            kindHint == 'risk' ||
            kindHint == 'riskitem' ||
            (call.arguments['riskItemId'] is String &&
                (call.arguments['riskItemId'] as String).trim().isNotEmpty);

        VibeToolResult? tryWbs() {
          final wbs = cost.findWbsItem(needle);
          if (wbs == null) return null;
          final profile =
              cost.findProfile(wbs.profileId) ??
              cost.resolveProfileForDiscipline(wbs.discipline);
          final dailyRate = profile.effectiveDailyRate(cost.deliveryMode);
          final gainPct = (cost.aiProductivity.enabled && wbs.aiEligible)
              ? cost.aiProductivity.gainPctFor(wbs.discipline)
              : 0.0;
          final aiExpectedDays = wbs.expectedDays * (1.0 - gainPct / 100.0);
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'wbs',
              'currency': cost.currency.code,
              'wbsItem': wbs.toJson(),
              'computed': <String, Object?>{
                'profileName': profile.name,
                'effectiveDailyRate': _round2(dailyRate),
                'expectedDays': _round2(wbs.expectedDays),
                'stdDevDays': _round2(wbs.stdDevDays),
                'classicExpectedCost': _round2(wbs.expectedDays * dailyRate),
                'aiGainPct': gainPct,
                'aiExpectedDays': _round2(aiExpectedDays),
                'aiExpectedCost': _round2(aiExpectedDays * dailyRate),
              },
            },
          );
        }

        VibeToolResult? tryRun() {
          final run = cost.findRunItem(needle);
          if (run == null) return null;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'run',
              'currency': cost.currency.code,
              'runItem': run.toJson(),
              'computed': <String, Object?>{
                'monthlyCostYear1': _round2(run.monthlyCost),
                'yearlyCostYear1': _round2(run.yearlyCostForYear(1)),
                'yearlyCostYear2': _round2(run.yearlyCostForYear(2)),
                'yearlyCostYear3': _round2(run.yearlyCostForYear(3)),
                'cumulative3Years': _round2(
                  run.yearlyCostForYear(1) +
                      run.yearlyCostForYear(2) +
                      run.yearlyCostForYear(3),
                ),
                'cumulative5Years': _round2(
                  run.yearlyCostForYear(1) +
                      run.yearlyCostForYear(2) +
                      run.yearlyCostForYear(3) +
                      run.yearlyCostForYear(4) +
                      run.yearlyCostForYear(5),
                ),
              },
            },
          );
        }

        VibeToolResult? tryRisk() {
          final risk = cost.findRiskItem(needle);
          if (risk == null) return null;
          final profile =
              cost.findProfile(risk.profileId) ??
              cost.resolveProfileForDiscipline(CostDiscipline.backend);
          final dailyRate = profile.effectiveDailyRate(cost.deliveryMode);
          final emvCost =
              risk.expectedDays * dailyRate + risk.expectedFixedCost;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'risk',
              'currency': cost.currency.code,
              'riskItem': risk.toJson(),
              'computed': <String, Object?>{
                'profileName': profile.name,
                'effectiveDailyRate': _round2(dailyRate),
                'expectedDays': _round2(risk.expectedDays),
                'expectedFixedCost': _round2(risk.expectedFixedCost),
                'emvTotalCost': _round2(emvCost),
              },
            },
          );
        }

        VibeToolResult? tryProfile() {
          final profile = cost.findProfile(needle);
          if (profile == null) return null;
          return VibeToolResult(
            callId: call.id,
            name: call.name,
            data: <String, Object?>{
              'kind': 'profile',
              'currency': cost.currency.code,
              'profile': profile.toJson(),
              'effectiveDailyRate': _round2(
                profile.effectiveDailyRate(cost.deliveryMode),
              ),
            },
          );
        }

        final resolvers = <VibeToolResult? Function()>[
          if (preferWbs) tryWbs,
          if (preferRun) tryRun,
          if (preferRisk) tryRisk,
          if (preferProfile) tryProfile,
          tryWbs,
          tryRun,
          tryRisk,
          tryProfile,
        ];

        for (final resolve in resolvers) {
          final found = resolve();
          if (found != null) return found;
        }

        return VibeToolResult.error(
          callId: call.id,
          name: call.name,
          message: 'Élément FinOps introuvable : $needle',
        );
      },
      'focus_cost_item': (call) async {
        final project = readProject();
        if (project == null) {
          return VibeToolResult.error(
            callId: call.id,
            name: call.name,
            message: 'Aucun projet actif.',
          );
        }
        final cost = project.costSpec;
        final stageRaw = (call.arguments['stage'] as String?)?.trim() ?? '';
        final genericRaw =
            (call.arguments['idOrCode'] as String?)?.trim() ?? '';
        final profileRaw =
            (call.arguments['profileId'] as String?)?.trim() ?? '';
        final wbsRaw = (call.arguments['wbsItemId'] as String?)?.trim() ?? '';
        final runRaw = (call.arguments['runItemId'] as String?)?.trim() ?? '';
        final riskRaw = (call.arguments['riskItemId'] as String?)?.trim() ?? '';

        CostForgeStage? resolvedStage = stageRaw.isEmpty
            ? null
            : CostForgeStage.fromJson(stageRaw);
        String? resolvedProfileId = profileRaw.isEmpty
            ? null
            : (cost.findProfile(profileRaw)?.id ?? profileRaw);
        String? resolvedWbsItemId = wbsRaw.isEmpty
            ? null
            : (cost.findWbsItem(wbsRaw)?.id ?? wbsRaw);
        String? resolvedRunItemId = runRaw.isEmpty
            ? null
            : (cost.findRunItem(runRaw)?.id ?? runRaw);
        String? resolvedRiskItemId = riskRaw.isEmpty
            ? null
            : (cost.findRiskItem(riskRaw)?.id ?? riskRaw);

        if (genericRaw.isNotEmpty) {
          final matchedWbs = cost.findWbsItem(genericRaw);
          final matchedRun = matchedWbs == null
              ? cost.findRunItem(genericRaw)
              : null;
          final matchedRisk = (matchedWbs == null && matchedRun == null)
              ? cost.findRiskItem(genericRaw)
              : null;
          final matchedProfile =
              (matchedWbs == null && matchedRun == null && matchedRisk == null)
              ? cost.findProfile(genericRaw)
              : null;
          if (matchedWbs != null) {
            resolvedWbsItemId ??= matchedWbs.id;
          } else if (matchedRun != null) {
            resolvedRunItemId ??= matchedRun.id;
          } else if (matchedRisk != null) {
            resolvedRiskItemId ??= matchedRisk.id;
          } else if (matchedProfile != null) {
            resolvedProfileId ??= matchedProfile.id;
          }
        }

        if (resolvedStage == null) {
          if (resolvedRiskItemId != null) {
            resolvedStage = CostForgeStage.tcoReviewExport;
          } else if (resolvedRunItemId != null) {
            resolvedStage = CostForgeStage.runOpex;
          } else if (resolvedWbsItemId != null) {
            resolvedStage = CostForgeStage.buildWbs;
          } else if (resolvedProfileId != null) {
            resolvedStage = CostForgeStage.rateCardAssumptions;
          }
        }

        onFocusCostItem?.call(
          stage: resolvedStage,
          profileId: resolvedProfileId,
          wbsItemId: resolvedWbsItemId,
          runItemId: resolvedRunItemId,
          riskItemId: resolvedRiskItemId,
        );

        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            if (resolvedStage != null) 'stage': resolvedStage.name,
            'focusedProfileId': ?resolvedProfileId,
            'focusedWbsItemId': ?resolvedWbsItemId,
            'focusedRunItemId': ?resolvedRunItemId,
            'focusedRiskItemId': ?resolvedRiskItemId,
          },
        );
      },
    };

    final enableUx =
        includeUxTools ??
        (onRunUxCoherenceAudit != null || onFocusUxItem != null);
    final enableQa =
        includeQaTools ??
        (onRunQaCoherenceAudit != null || onFocusQaItem != null);
    final enableCost =
        includeCostTools ??
        (onRunCostCoherenceAudit != null || onFocusCostItem != null);
    final effectiveNames =
        toolNames ??
        <String>{
          ...specToolNames,
          if (enableUx) ...uxToolNames,
          if (enableQa) ...qaToolNames,
          if (enableCost) ...costToolNames,
        };

    return VibeAppToolRegistry([
      for (final decl in declarations)
        if (effectiveNames.contains(decl.name))
          VibeRegisteredTool(declaration: decl, handler: handlers[decl.name]!),
    ]);
  }

  /// Formate un résumé concis pour l'affichage dans [VibeToolTrace] côté chat.
  static String summarizeResult(VibeToolCall call, VibeToolResult result) {
    final data = result.data;
    if (result.isError) {
      final err = data['error'];
      return err is String && err.trim().isNotEmpty ? err.trim() : 'Erreur';
    }
    switch (call.name) {
      case 'get_lexicon_and_synonyms':
        return '${data['termCount'] ?? 0} terme(s) lu(s)';
      case 'get_requirements_summary':
        return '${data['functionalRequirementCount'] ?? 0} EXF, ${data['useCaseCount'] ?? 0} cas d’usage';
      case 'inspect_business_object':
        if (data['object'] is Map) {
          final obj = data['object'] as Map;
          return '${obj['technicalName']} (${data['totalAttributeCount'] ?? 0}/200 attr.)';
        }
        return '${data['objectCount'] ?? 0} objet(s) métier(s)';
      case 'get_business_rules':
        return '${data['ruleCount'] ?? 0} règle(s) RG';
      case 'get_debug_entries':
        return '${data['returnedCount'] ?? 0} entrée(s) debug';
      case 'run_coherence_audit':
        return '${data['issueCount'] ?? 0} point(s) (${data['errorCount'] ?? 0} erreur(s))';
      case 'validate_yaml_light_schema':
        return data['valid'] == true
            ? 'YAML valide (${data['objectCount'] ?? 0} objet(s))'
            : 'YAML invalide';
      case 'extract_array_to_business_object':
        return 'Extrait vers ${data['technicalName'] ?? 'objet dédié'}';
      case 'focus_stage_or_object':
        if (data['focusedAttribute'] is String) {
          return 'Sélection : ${data['focusedAttribute']}';
        }
        return 'Focus sur ${data['stage'] ?? 'étape'}';
      case 'filter_business_objects':
        final q = (data['query'] as String?) ?? '';
        if (q.isEmpty) return 'Filtre réinitialisé';
        return 'Filtre "$q" (${data['matchingObjectCount'] ?? 0} obj.)';
      case 'get_ux_overview':
        return '${data['journeyCount'] ?? 0} parcours, ${data['routeCount'] ?? 0} route(s), ${data['screenCount'] ?? 0} écran(s)';
      case 'inspect_ux_screen':
        if (data['screen'] is Map) {
          final scr = data['screen'] as Map;
          return 'Écran ${scr['code'] ?? ''} — ${scr['name'] ?? ''}'.trim();
        }
        if (data['journey'] is Map) {
          final jrn = data['journey'] as Map;
          return 'Parcours ${jrn['code'] ?? ''} — ${jrn['name'] ?? ''}'.trim();
        }
        return '${data['screenCount'] ?? 0} écran(s), ${data['journeyCount'] ?? 0} parcours';
      case 'run_ux_coherence_audit':
        return '${data['issueCount'] ?? 0} point(s) UX (${data['errorCount'] ?? 0} erreur(s))';
      case 'focus_ux_item':
        if (data['focusedScreenId'] is String) {
          final z = data['focusedZone'];
          return z is String
              ? 'Focus écran ${data['focusedScreenId']} ($z)'
              : 'Focus écran ${data['focusedScreenId']}';
        }
        if (data['focusedRouteId'] is String) {
          return 'Focus route ${data['focusedRouteId']}';
        }
        if (data['focusedJourneyId'] is String) {
          return 'Focus parcours ${data['focusedJourneyId']}';
        }
        return 'Focus UX ${data['stage'] ?? 'atelier'}';
      case 'get_qa_overview':
        return '${data['fixtureCount'] ?? 0} fixture(s), ${data['featureCount'] ?? 0} feature(s) (${data['scenarioCount'] ?? 0} scén.), ${data['tddSuiteCount'] ?? 0} suite(s) TDD';
      case 'inspect_qa_artifact':
        if (data['fixture'] is Map) {
          final fix = data['fixture'] as Map;
          return 'Fixture ${fix['code'] ?? ''} — ${fix['name'] ?? ''}'.trim();
        }
        if (data['scenario'] is Map) {
          final sc = data['scenario'] as Map;
          return 'Scénario ${sc['code'] ?? ''} — ${sc['title'] ?? ''}'.trim();
        }
        if (data['feature'] is Map) {
          final feat = data['feature'] as Map;
          return 'Feature ${feat['code'] ?? ''} — ${feat['title'] ?? ''}'
              .trim();
        }
        if (data['tddSuite'] is Map) {
          final suite = data['tddSuite'] as Map;
          return 'Suite ${suite['code'] ?? ''} — ${suite['name'] ?? ''}'.trim();
        }
        return '${data['fixtureCount'] ?? 0} fixture(s), ${data['featureCount'] ?? 0} feature(s), ${data['tddSuiteCount'] ?? 0} suite(s) TDD';
      case 'run_qa_coherence_audit':
        return '${data['issueCount'] ?? 0} point(s) QA (${data['errorCount'] ?? 0} erreur(s))';
      case 'focus_qa_item':
        if (data['focusedTddSuiteId'] is String) {
          return 'Focus suite TDD ${data['focusedTddSuiteId']}';
        }
        if (data['focusedScenarioId'] is String) {
          return 'Focus scénario ${data['focusedScenarioId']}';
        }
        if (data['focusedFeatureId'] is String) {
          return 'Focus feature ${data['focusedFeatureId']}';
        }
        if (data['focusedFixtureId'] is String) {
          return 'Focus fixture ${data['focusedFixtureId']}';
        }
        return 'Focus QA ${data['stage'] ?? 'atelier'}';
      case 'get_cost_overview':
        return '${data['wbsItemCount'] ?? 0} lot(s) WBS, ${data['runItemCount'] ?? 0} poste(s) Run, ${data['riskItemCount'] ?? 0} risque(s)';
      case 'inspect_cost_item':
        if (data['wbsItem'] is Map) {
          final wbs = data['wbsItem'] as Map;
          return 'Lot ${wbs['code'] ?? ''} — ${wbs['title'] ?? ''}'.trim();
        }
        if (data['runItem'] is Map) {
          final run = data['runItem'] as Map;
          return 'Poste ${run['code'] ?? ''} — ${run['name'] ?? ''}'.trim();
        }
        if (data['riskItem'] is Map) {
          final rsk = data['riskItem'] as Map;
          return 'Risque ${rsk['code'] ?? ''} — ${rsk['title'] ?? ''}'.trim();
        }
        if (data['profile'] is Map) {
          final prf = data['profile'] as Map;
          return 'Profil ${prf['code'] ?? ''} — ${prf['name'] ?? ''}'.trim();
        }
        return '${data['wbsItemCount'] ?? 0} WBS, ${data['runItemCount'] ?? 0} Run, ${data['riskItemCount'] ?? 0} risque(s)';
      case 'focus_cost_item':
        if (data['focusedWbsItemId'] is String) {
          return 'Focus lot WBS ${data['focusedWbsItemId']}';
        }
        if (data['focusedRunItemId'] is String) {
          return 'Focus poste Run ${data['focusedRunItemId']}';
        }
        if (data['focusedRiskItemId'] is String) {
          return 'Focus risque ${data['focusedRiskItemId']}';
        }
        if (data['focusedProfileId'] is String) {
          return 'Focus profil ${data['focusedProfileId']}';
        }
        return 'Focus Coûts ${data['stage'] ?? 'atelier'}';
    }
    return 'OK';
  }

  /// Calcule de manière autonome un résumé financier JSON complet ([CostForgeSpec])
  /// couvrant les lots Build (MVP, V1, Cible, Total), le Run 1/3/5 ans, les risques EMV et le TCO 1/3/5 ans.
  static Map<String, Object?> buildCostSummaryJson(CostForgeSpec cost) {
    final mvpLot = _computeLotSummaryJson(
      cost,
      cost.wbsItems.where((w) => w.priority == RequirementPriority.must).toList(),
    );
    final v1Lot = _computeLotSummaryJson(
      cost,
      cost.wbsItems
          .where(
            (w) =>
                w.priority == RequirementPriority.must ||
                w.priority == RequirementPriority.should,
          )
          .toList(),
    );
    final fullLot = _computeLotSummaryJson(
      cost,
      cost.wbsItems
          .where((w) => w.priority != RequirementPriority.wont)
          .toList(),
    );
    final allLot = _computeLotSummaryJson(cost, cost.wbsItems);

    var monthlyRunY1 = 0.0;
    var yearlyRunY1 = 0.0;
    var yearlyRunY2 = 0.0;
    var yearlyRunY3 = 0.0;
    var yearlyRunY4 = 0.0;
    var yearlyRunY5 = 0.0;
    for (final run in cost.runItems) {
      monthlyRunY1 += run.monthlyCost;
      yearlyRunY1 += run.yearlyCostForYear(1);
      yearlyRunY2 += run.yearlyCostForYear(2);
      yearlyRunY3 += run.yearlyCostForYear(3);
      yearlyRunY4 += run.yearlyCostForYear(4);
      yearlyRunY5 += run.yearlyCostForYear(5);
    }
    final cumulativeRun3Y = yearlyRunY1 + yearlyRunY2 + yearlyRunY3;
    final cumulativeRun5Y = cumulativeRun3Y + yearlyRunY4 + yearlyRunY5;

    var riskEmvDays = 0.0;
    var riskEmvCost = 0.0;
    for (final risk in cost.riskItems) {
      final profile =
          cost.findProfile(risk.profileId) ??
          cost.resolveProfileForDiscipline(CostDiscipline.backend);
      final dailyRate = profile.effectiveDailyRate(cost.deliveryMode);
      riskEmvDays += risk.expectedDays;
      riskEmvCost += risk.expectedDays * dailyRate + risk.expectedFixedCost;
    }

    final effectiveBuild = (fullLot['effectiveTotalCost'] as num).toDouble();
    final tco1Y = effectiveBuild + riskEmvCost + yearlyRunY1;
    final tco3Y = effectiveBuild + riskEmvCost + cumulativeRun3Y;
    final tco5Y = effectiveBuild + riskEmvCost + cumulativeRun5Y;

    return <String, Object?>{
      'currency': cost.currency.code,
      'mvpLot': mvpLot,
      'v1Lot': v1Lot,
      'fullLot': fullLot,
      'allLot': allLot,
      'monthlyRunYear1': _round2(monthlyRunY1),
      'yearlyRunYear1': _round2(yearlyRunY1),
      'yearlyRunYear2': _round2(yearlyRunY2),
      'yearlyRunYear3': _round2(yearlyRunY3),
      'cumulativeRun3Years': _round2(cumulativeRun3Y),
      'cumulativeRun5Years': _round2(cumulativeRun5Y),
      'riskEmvDays': _round2(riskEmvDays),
      'riskEmvCost': _round2(riskEmvCost),
      'tco1Year': _round2(tco1Y),
      'tco3Years': _round2(tco3Y),
      'tco5Years': _round2(tco5Y),
    };
  }

  static Map<String, Object?> _computeLotSummaryJson(
    CostForgeSpec cost,
    List<CostWbsItemSpec> items,
  ) {
    var optDays = 0.0;
    var expDays = 0.0;
    var pessDays = 0.0;
    var varianceSum = 0.0;
    var classicWbsCost = 0.0;
    var aiWbsDays = 0.0;
    var aiWbsCost = 0.0;

    for (final item in items) {
      final profile =
          cost.findProfile(item.profileId) ??
          cost.resolveProfileForDiscipline(item.discipline);
      final rate = profile.effectiveDailyRate(cost.deliveryMode);
      final itemExp = item.expectedDays;
      optDays += item.optimisticDays;
      expDays += itemExp;
      pessDays += item.pessimisticDays;
      varianceSum += item.varianceDays;
      classicWbsCost += itemExp * rate;

      final gainPct = (cost.aiProductivity.enabled && item.aiEligible)
          ? cost.aiProductivity.gainPctFor(item.discipline)
          : 0.0;
      final itemAiDays = itemExp * (1.0 - gainPct / 100.0);
      aiWbsDays += itemAiDays;
      aiWbsCost += itemAiDays * rate;
    }

    final p80Days = expDays + 0.8416212335729143 * math.sqrt(varianceSum);
    final ratios = cost.transverseRatios;
    final pmRate = cost
        .resolveProfileForDiscipline(CostDiscipline.projectManagement)
        .effectiveDailyRate(cost.deliveryMode);
    final archRate = cost
        .resolveProfileForDiscipline(CostDiscipline.devSecOps)
        .effectiveDailyRate(cost.deliveryMode);
    final qaRate = cost
        .resolveProfileForDiscipline(CostDiscipline.qaTesting)
        .effectiveDailyRate(cost.deliveryMode);
    final weightedBaseRate = expDays > 0.0
        ? classicWbsCost / expDays
        : cost.toEnterpriseRateCard().averageDailyRate(cost.deliveryMode);

    final classicPmDays = expDays * (ratios.projectManagementPct / 100.0);
    final classicArchDays = expDays * (ratios.architectureDevOpsPct / 100.0);
    final classicQaDays = expDays * (ratios.transverseQaPct / 100.0);
    final classicSubDays =
        expDays + classicPmDays + classicArchDays + classicQaDays;
    final classicSubCost =
        classicWbsCost +
        classicPmDays * pmRate +
        classicArchDays * archRate +
        classicQaDays * qaRate;
    final classicContDays = classicSubDays * (ratios.contingencyPct / 100.0);
    final classicContCost = classicSubCost * (ratios.contingencyPct / 100.0);
    final classicTotalDays = classicSubDays + classicContDays;
    final classicTotalCost = classicSubCost + classicContCost;

    final aiPmGain = cost.aiProductivity.gainPctFor(
      CostDiscipline.projectManagement,
    );
    final aiArchGain = cost.aiProductivity.gainPctFor(CostDiscipline.devSecOps);
    final aiQaGain = cost.aiProductivity.gainPctFor(CostDiscipline.qaTesting);
    final aiPmDays =
        aiWbsDays *
        (ratios.projectManagementPct / 100.0) *
        (1.0 - aiPmGain / 100.0);
    final aiArchDays =
        aiWbsDays *
        (ratios.architectureDevOpsPct / 100.0) *
        (1.0 - aiArchGain / 100.0);
    final aiQaDays =
        aiWbsDays *
        (ratios.transverseQaPct / 100.0) *
        (1.0 - aiQaGain / 100.0);
    final aiSubDays = aiWbsDays + aiPmDays + aiArchDays + aiQaDays;
    final aiSubCost =
        aiWbsCost +
        aiPmDays * pmRate +
        aiArchDays * archRate +
        aiQaDays * qaRate;
    final aiContDays = aiSubDays * (ratios.contingencyPct / 100.0);
    final aiContCost = aiSubCost * (ratios.contingencyPct / 100.0);
    final aiTotalDays = aiSubDays + aiContDays;
    final aiTotalCost = aiSubCost + aiContCost;

    final effectiveTotalDays = cost.aiProductivity.enabled
        ? aiTotalDays
        : classicTotalDays;
    final effectiveTotalCost = cost.aiProductivity.enabled
        ? aiTotalCost
        : classicTotalCost;
    final p80Factor = expDays > 0.0 ? (p80Days / expDays) : 1.0;
    final effectiveP80Cost = expDays > 0.0
        ? effectiveTotalCost * p80Factor
        : p80Days * weightedBaseRate;

    return <String, Object?>{
      'itemCount': items.length,
      'wbsOptimisticDays': _round2(optDays),
      'wbsExpectedDays': _round2(expDays),
      'wbsPessimisticDays': _round2(pessDays),
      'wbsP80Days': _round2(p80Days),
      'classicTotalDays': _round2(classicTotalDays),
      'classicTotalCost': _round2(classicTotalCost),
      'aiTotalDays': _round2(aiTotalDays),
      'aiTotalCost': _round2(aiTotalCost),
      'effectiveTotalDays': _round2(effectiveTotalDays),
      'effectiveTotalCost': _round2(effectiveTotalCost),
      'effectiveP80Cost': _round2(effectiveP80Cost),
      'aiSavedDays': _round2(classicTotalDays - aiTotalDays),
      'aiSavedCost': _round2(classicTotalCost - aiTotalCost),
    };
  }

  static double _round2(double value) =>
      value.isFinite ? (value * 100.0).roundToDouble() / 100.0 : 0.0;

  static ({GherkinFeatureSpec feature, GherkinScenarioSpec scenario})?
  _findScenarioInQa(QaForgeSpec qa, String idOrCodeOrTitle) {
    final needle = idOrCodeOrTitle.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final feature in qa.features) {
      for (final sc in feature.scenarios) {
        if (sc.id.toLowerCase() == needle ||
            (sc.code.isNotEmpty && sc.code.toLowerCase() == needle)) {
          return (feature: feature, scenario: sc);
        }
      }
    }
    for (final feature in qa.features) {
      for (final sc in feature.scenarios) {
        if (sc.title.toLowerCase() == needle) {
          return (feature: feature, scenario: sc);
        }
      }
    }
    return null;
  }

  static ({TddTestSuiteSpec suite, TddTestCaseSpec testCase})? _findTddCaseInQa(
    QaForgeSpec qa,
    String idOrCodeOrTitle,
  ) {
    final needle = idOrCodeOrTitle.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final suite in qa.tddSuites) {
      for (final c in suite.cases) {
        if (c.id.toLowerCase() == needle ||
            (c.code.isNotEmpty && c.code.toLowerCase() == needle)) {
          return (suite: suite, testCase: c);
        }
      }
    }
    for (final suite in qa.tddSuites) {
      for (final c in suite.cases) {
        if (c.title.toLowerCase() == needle) {
          return (suite: suite, testCase: c);
        }
      }
    }
    return null;
  }

  static ({List<String> ids, List<String> names})? _resolveAttributePath(
    List<BusinessAttribute> attrs,
    String rawQuery,
  ) {
    final segments = rawQuery
        .split('.')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;

    ({List<String> ids, List<String> names})? matchPath(
      List<BusinessAttribute> list,
      List<String> remaining,
    ) {
      final headLower = remaining.first.toLowerCase();
      for (final a in list) {
        if (a.id.toLowerCase() == headLower ||
            a.name.toLowerCase() == headLower) {
          if (remaining.length == 1) {
            return (ids: [a.id], names: [a.name]);
          }
          final child = matchPath(a.children, remaining.sublist(1));
          if (child != null) {
            return (ids: [a.id, ...child.ids], names: [a.name, ...child.names]);
          }
        }
      }
      return null;
    }

    final exact = matchPath(attrs, segments);
    if (exact != null) return exact;

    if (segments.length == 1) {
      final needle = segments.first.toLowerCase();
      ({List<String> ids, List<String> names})? searchRec(
        List<BusinessAttribute> list,
      ) {
        for (final a in list) {
          if (a.id.toLowerCase() == needle || a.name.toLowerCase() == needle) {
            return (ids: [a.id], names: [a.name]);
          }
          final sub = searchRec(a.children);
          if (sub != null) {
            return (ids: [a.id, ...sub.ids], names: [a.name, ...sub.names]);
          }
        }
        return null;
      }

      return searchRec(attrs);
    }
    return null;
  }

  static int _countMatchingAttributes(
    List<BusinessAttribute> attrs,
    String lowerQuery,
  ) {
    var count = 0;
    for (final a in attrs) {
      final matches =
          lowerQuery.isEmpty ||
          a.name.toLowerCase().contains(lowerQuery) ||
          a.type.name.toLowerCase().contains(lowerQuery) ||
          a.type.dslKeyword.toLowerCase().contains(lowerQuery) ||
          a.description.toLowerCase().contains(lowerQuery);
      if (matches) count++;
      count += _countMatchingAttributes(a.children, lowerQuery);
    }
    return count;
  }

  static String _singularizePascal(String raw) {
    final cleaned = raw.trim();
    final singular = cleaned.endsWith('s') && cleaned.length > 2
        ? cleaned.substring(0, cleaned.length - 1)
        : cleaned;
    return _toPascal(singular);
  }

  static String _toPascal(String input) {
    final words = input
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'ObjetMetier';
    return words.map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();
  }

  static String _toCamel(String pascal) => pascal.isEmpty
      ? 'parent'
      : '${pascal[0].toLowerCase()}${pascal.substring(1)}';
}
