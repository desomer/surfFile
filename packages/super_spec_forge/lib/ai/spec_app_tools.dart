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
import '../services/spec_coherence_analyzer.dart';
import '../services/spec_schema_dsl_bridge.dart';

/// Construit et documente les outils exposés aux agents IA de `super_spec_forge`.
abstract final class SpecForgeToolRegistry {
  /// Guide succinct injecté dans le guide statique des agents.
  static String toolsGuide() => '''
OUTILS D'INTROSPECTION, VALIDATION ET ACTION DISPONIBLES :
1. `get_lexicon_and_synonyms` : recherche les termes canoniques, définitions et synonymes rejetés dans le lexique métier.
2. `get_requirements_summary` : liste les modules, exigences fonctionnelles (EXF), cas d'usage et exigences non fonctionnelles (ENF).
3. `inspect_business_object` : lit le détail complet d'un objet métier (sous-objets, attributs, compteur N/200, tableaux, relations, cycle de vie, YAML Light).
4. `get_business_rules` : liste les règles de gestion RG-xxx existantes (filtrables par objet ou catégorie).
5. `get_debug_entries` : consulte les derniers journaux et erreurs capturés dans la console debug.
6. `run_coherence_audit` : exécute l'analyse de cohérence inter-étapes et signale références cassées ou dépassements > 200.
7. `validate_yaml_light_schema` : valide un bloc YAML Light via Yaml2JsonSchemasParser et vérifie les règles <= 200 attributs / <= 200 lignes/tableau.
8. `extract_array_to_business_object` : extrait un tableau imbriqué vers un nouvel objet métier dédié relié en 1:N.
9. `focus_stage_or_object` : bascule l'interface sur une étape du wizard et sélectionne éventuellement un objet métier cible.
Utilise ces outils à bon escient avant de conclure lorsque tu as besoin de vérifier des détails, valider un schéma ou auditer la cohérence.''';

  /// Déclarations statiques des 9 outils exposés au modèle Gemini.
  static const List<VibeToolDeclaration> declarations = <VibeToolDeclaration>[
    VibeToolDeclaration(
      name: 'get_lexicon_and_synonyms',
      description:
          'Consulte le lexique métier (termes canoniques, définitions, synonymes à unifier, conventions).',
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
      description:
          'Liste les modules, exigences fonctionnelles (EXF), cas d’usage et exigences non fonctionnelles (ENF) du cahier des charges.',
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
      description:
          'Retourne le détail complet d’un objet métier (sous-objets, compteur N/200 attributs, tableaux imbriqués, relations, cycle de vie et YAML Light optionnel), ou la liste synthétique si objectIdOrName est omis.',
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
      description:
          'Liste les règles de gestion RG-xxx existantes, filtrables par objet cible ou catégorie.',
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
      description:
          'Lit les derniers journaux et erreurs capturés dans la console debug (debugEntries).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'type': <String, Object?>{
            'type': 'string',
            'description': 'Filtre optionnel : error, log ou all (error par défaut).',
          },
          'query': <String, Object?>{
            'type': 'string',
            'description': 'Filtre texte optionnel dans le message ou la pile.',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'description': 'Nombre maximal d’entrées retournées (1..50, 20 par défaut).',
          },
        },
      },
    ),
    VibeToolDeclaration(
      name: 'run_coherence_audit',
      description:
          'Exécute l’analyse de cohérence statique inter-étapes sur l’ensemble du projet (références cassées, états manquants, limites > 200).',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
    VibeToolDeclaration(
      name: 'validate_yaml_light_schema',
      description:
          'Valide un schéma YAML « JSON Schemas Light » via Yaml2JsonSchemasParser et vérifie les règles <= 200 attributs et <= 200 lignes par tableau.',
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
      description:
          'Extrait un attribut tableau d’un objet métier vers un nouvel objet métier dédié relié en 1:N (recommandé dès > 200 lignes fonctionnelles).',
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
      description:
          'Positionne l’interface du wizard sur une étape donnée et sélectionne éventuellement un objet métier.',
      parametersSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'stage': <String, Object?>{
            'type': 'string',
            'description': 'Nom de l’étape (lexicon, vision, specifications, businessObjects, businessRules, reviewExport).',
          },
          'objectId': <String, Object?>{
            'type': 'string',
            'description': 'Identifiant ou nom technique de l’objet à sélectionner (optionnel).',
          },
        },
        'required': <String>['stage'],
      },
    ),
  ];

  /// Construit un [VibeAppToolRegistry] connecté au projet courant et aux callbacks de mutation/navigation.
  static VibeAppToolRegistry build({
    required SpecForgeProject? Function() readProject,
    required Future<void> Function(SpecForgeProject updated) onUpdateProject,
    required Future<void> Function(SpecForgeStage stage) onNavigateStage,
    required void Function(String? objectId) onFocusObject,
    CompanyGlossary Function()? readCompanyGlossary,
    BusinessObjectModelPreferences Function()? readModelPreferences,
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
        final q = (call.arguments['query'] as String?)?.trim().toLowerCase() ?? '';
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
        final moduleFilter = (call.arguments['moduleId'] as String?)?.trim() ?? '';
        final priorityRaw = (call.arguments['priority'] as String?)?.trim() ?? '';
        final priorityFilter = priorityRaw.isEmpty
            ? null
            : RequirementPriority.fromJson(priorityRaw);
        final reqs = project.cahierDesCharges.functionalRequirements.where((r) {
          if (moduleFilter.isNotEmpty && r.moduleId != moduleFilter) return false;
          if (priorityFilter != null && r.priority != priorityFilter) return false;
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
              for (final n in project.cahierDesCharges.nonFunctionalRequirements)
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
            (call.arguments['type'] as String?)?.trim().toLowerCase() ?? 'error';
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
        final issues = SpecCoherenceAnalyzer.analyze(
          project,
          companyGlossary: readCompanyGlossary?.call(),
          modelPreferences: readModelPreferences?.call(),
        );
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
        await onUpdateProject(project.copyWith(businessObjects: nextObjects));
        onFocusObject(newId);
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
        final stage = SpecForgeStage.fromJson(stageName);
        await onNavigateStage(stage);
        final objKey = (call.arguments['objectId'] as String?)?.trim() ?? '';
        String? resolvedId;
        if (objKey.isNotEmpty) {
          resolvedId = project.findBusinessObject(objKey)?.id;
          onFocusObject(resolvedId);
        }
        return VibeToolResult(
          callId: call.id,
          name: call.name,
          data: <String, Object?>{
            'stage': stage.name,
            'focusedObjectId': ?resolvedId,
          },
        );
      },
    };

    return VibeAppToolRegistry([
      for (final decl in declarations)
        VibeRegisteredTool(
          declaration: decl,
          handler: handlers[decl.name]!,
        ),
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
        return 'Focus sur ${data['stage'] ?? 'étape'}';
    }
    return 'OK';
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

  static String _toCamel(String pascal) =>
      pascal.isEmpty ? 'parent' : '${pascal[0].toLowerCase()}${pascal.substring(1)}';
}
