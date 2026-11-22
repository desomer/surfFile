/// Registre des outils IA métier et de diagnostic pour `super_spec_forge` ([SpecForgeToolRegistry]).
///
/// Réutilise les contrats [VibeAppToolRegistry], [VibeToolDeclaration],
/// [VibeToolCall] et [VibeToolResult] de `super_container_layout`.
library;

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/business_rule_spec.dart';
import '../models/company_glossary.dart';
import '../models/spec_cahier_des_charges.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/ux/ux_coherence_issue.dart';
import '../models/ux/ux_forge_stage.dart';
import '../models/ux/ux_screen_spec.dart';
import '../services/spec_coherence_analyzer.dart';
import '../services/spec_schema_dsl_bridge.dart';

/// Construit et documente les outils exposés aux agents IA de `super_spec_forge`.
abstract final class SpecForgeToolRegistry {
  /// Ensemble des 10 outils historiques du wizard de spécification métier.
  static const Set<String> specToolNames = <String>{
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'inspect_business_object',
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
      'inspect_business_object',
      'lit le détail complet d\'un objet métier (sous-objets, attributs, compteur N/200, tableaux, relations, cycle de vie, YAML Light).',
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

  /// Déclarations statiques des 14 outils (10 Spec + 4 UX) exposés au modèle Gemini.
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
            'description': 'Nom de l’étape (lexicon, vision, specifications, businessObjects, businessRules, reviewExport).',
          },
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant, nom technique ou nom métier de l’objet à sélectionner (optionnel).',
          },
          'attributePath': <String, Object?>{
            'type': 'string',
            'description': 'Nom ou chemin pointé de l’attribut à sélectionner dans l’objet (ex. "statut" ou "adresseLivraison.codePostal").',
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
  ];

  /// Crée un [VibeAppToolRegistry] complet incluant par défaut les outils Spec et les 4 outils UX.
  static VibeAppToolRegistry create({
    required SpecForgeProject? Function() readProject,
    Future<void> Function(SpecForgeProject updated)? onUpdateProject,
    Future<void> Function(SpecForgeStage stage)? onNavigateStage,
    void Function(String? objectId)? onFocusObject,
    void Function({String? objectId, List<String> attributePath})?
    onFocusSelection,
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
    Set<String>? toolNames,
    bool includeUxTools = true,
    bool Function(SpecCoherenceIssue issue)? coherenceIssueFilter,
  }) => build(
    readProject: readProject,
    onUpdateProject: onUpdateProject,
    onNavigateStage: onNavigateStage,
    onFocusObject: onFocusObject,
    onFocusSelection: onFocusSelection,
    onFilterBusinessObjects: onFilterBusinessObjects,
    readCompanyGlossary: readCompanyGlossary,
    readModelPreferences: readModelPreferences,
    onRunUxCoherenceAudit: onRunUxCoherenceAudit,
    onFocusUxItem: onFocusUxItem,
    toolNames: toolNames,
    includeUxTools: includeUxTools,
    coherenceIssueFilter: coherenceIssueFilter,
  );

  /// Construit un [VibeAppToolRegistry] connecté au projet courant et aux callbacks de mutation/navigation.
  ///
  /// [toolNames] restreint les outils enregistrés ; lorsqu'il est omis, les 4
  /// outils UX sont activés dès que [includeUxTools] vaut `true` ou qu'un
  /// callback UX ([onRunUxCoherenceAudit] / [onFocusUxItem]) est fourni.
  static VibeAppToolRegistry build({
    required SpecForgeProject? Function() readProject,
    Future<void> Function(SpecForgeProject updated)? onUpdateProject,
    Future<void> Function(SpecForgeStage stage)? onNavigateStage,
    void Function(String? objectId)? onFocusObject,
    void Function({String? objectId, List<String> attributePath})?
    onFocusSelection,
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
    Set<String>? toolNames,
    bool? includeUxTools,
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
            'terms': [for (final t in terms) t.toJson()],
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
    };

    final enableUx =
        includeUxTools ??
        (onRunUxCoherenceAudit != null || onFocusUxItem != null);
    final effectiveNames = toolNames ?? (enableUx ? null : specToolNames);

    return VibeAppToolRegistry([
      for (final decl in declarations)
        if (effectiveNames == null || effectiveNames.contains(decl.name))
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
    }
    return 'OK';
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
