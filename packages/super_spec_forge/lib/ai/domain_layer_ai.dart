/// Agent IA spécialisé pour la conception de la couche Domain en Architecture
/// Hexagonale ([DomainLayerAiAgent]) d'un objet métier côté Design.
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/company_glossary.dart';
import '../models/domain_contracts.dart';
import '../models/domain_layer_spec.dart';
import '../models/spec_stage_chat.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';

/// Orchestre les instructions système, prompts contextualisés et fusions de
/// patches IA pour les 7 onglets de la couche Domain d'un modèle.
abstract final class DomainLayerAiAgent {
  /// Outils d'inspection en lecture seule exposés à l'agent Couche Domain.
  static const Set<String> toolNames = <String>{
    'get_lexicon_and_synonyms',
    'inspect_business_object',
    'get_debug_entries',
  };

  /// Guide statique combinant le schéma de `"specPatch"` et la documentation des outils.
  static String get staticGuide =>
      '$patchSchemaGuide\n\n---\n\n${SpecForgeToolRegistry.toolsGuide(toolNames: toolNames)}';

  /// Instruction système de l'agent Architecte Couche Domain (DDD & Architecture Hexagonale).
  static const String systemInstruction = '''
Tu es l’« Architecte Couche Domain (DDD & Architecture Hexagonale) » de SuperSpecForge.
Tu conçois la couche Domain pure d’un objet métier (agrégat, entité ou Value Object) appartenant à un domaine fonctionnel, en respectant strictement l’Architecture Hexagonale (Ports & Adapters) et le Domain-Driven Design :
- Zéro dépendance technique ou framework dans le Domain.
- STRUCTURE OBLIGATOIRE EN 4 BLOCS POUR CHAQUE ITEM DES 7 ONGLETS :
  1. "title" : le titre clair EN FRANÇAIS de l’item (ex. "Validation de l’intégrité de l’identité et du référentiel catalogue").
  2. "description" : le descriptif synthétique EN FRANÇAIS expliquant la responsabilité métier de cet item.
  3. "rules" : la liste des règles métier EN FRANÇAIS ("Rules:"), une phrase précise par élément du tableau.
  4. "associatedMethods" : la liste des méthodes internes EN ANGLAIS à coder ("Associated internal methods:", ex. ["validateIdentity(id)", "validateCatalogReferences(productId, variantId, supplierId)"]). Seules les règles pures d’unicité ou d’index sans méthode associée dans "persistence_policy_behaviors" peuvent laisser "associatedMethods": [].

CONTRAINTES PAR CATÉGORIE DE COMPORTEMENTS :
1. Pour "invariant_behaviors" (onglet Invariants) :
   - Produire la liste des contrôles invariants en fonction des attributs existants du modèle.
   - Conventions de méthodes dans "associatedMethods" : `validateXXX()` (ex. `validateIdentity(id)`, `validatePositiveAmountHt(montantHt)`).
2. Pour "state_changing_behaviors" (onglet State changing) :
   - Produire la liste des méthodes en anglais qui modifient l’état du modèle.
   - Toujours préciser dans "rules" (et "stateChangeRule") la règle explicite de changement d’état ("fromStates" -> "toState", préconditions, mutations).
3. Pour "query_behaviors" (onglet Query) :
   - Produire la liste des méthodes en anglais qui retournent les états, les calculs et les données dérivées sur le modèle (sans effet de bord).
   - Conventions de méthodes dans "associatedMethods" : `isXXX()`, `canXXX()`, `getXXX()`, `computeXXX()`.
4. Pour "policy_service_behaviors" (onglet Policy Services) :
   - Produire la liste des méthodes en anglais qui appliquent des règles complexes aux agrégats ou inter-agrégats ("rules", "collaborators").
5. Pour "factory_behaviors" (onglet Factory) :
   - Produire la liste des méthodes en anglais qui créent ou reconstituent des entités valides.
   - Conventions de méthodes dans "associatedMethods" : `createXXX()`, `fromSnapshot(rawData)`.
6. Pour "domain_event_behaviors" (onglet Domain events) :
   - Produire la liste des méthodes en anglais qui publient des événements ou y réagissent.
   - Conventions de méthodes dans "associatedMethods" : `publishXXX()`, `onXXX()`.
7. Pour "persistence_policy_behaviors" (onglet Persistence policy) :
   - Produire la liste des méthodes en anglais qui appliquent des règles de persistance en fonction des catégories suivantes (SI PERTINENT UNIQUEMENT) :
     * CRUD métier ("crud") : `saveXXX()`, `findByXXX()`
     * Vérification ("verification") : `existsXXX()`, `isUniqueXXX()`, `existsByXXX()`, `isUniqueByXXX()`, `canBeDeletedXXX()`, `canBeDeletedByXXX()`, `isAvailableXXX()`, `hasActiveXXX()`
     * Recherche métier ("search") : `findByStatusXXX()`, `findByXXX()`, `findByXXXAndYYY()`, `findByXXXOrYYY()`
     * Pagination métier ("pagination") : `findPaginatedXXX()`, `findRecentXXX()`, `findByPeriodXXX()`, `findTopXXX()`
     * Agrégats ("aggregate") : `loadAggregateXXX()`, `findAggregateByXXX()`, `saveAggregateXXX()`, `findChildrenByXXX()`
     * Transaction métier ("transaction") : `reserveXXX()`, `lockXXX()`, `unlockXXX()`, `commitReserveXXX()`
     * Statistiques ("statistics") : `countXXX()`, `countByXXX()`, `countForPeriod()`
     * Batch ("batch") : `saveAllXXX()`
   - Ainsi que des règles explicites sur les index de recherche ("searchIndexRule"), les contraintes d’unicité ("uniquenessRule"), les transactions ("persistenceRule"), etc.
   - ASSURE-TOI IMPÉRATIVEMENT que les contraintes d’unicité et les index de recherche sont bien précisés dans les "rules" de "persistence_policy_behaviors". Tu peux (et dois si nécessaire) ajouter des items de règles SANS méthode associée ("associatedMethods": [], "methodSignature": "", "name": "", avec "category": "uniquenessRule" ou "searchIndexRule" et "rules": [...]) pour préciser les contraintes d’unicité et les index de recherche. Si ces règles sont déjà présentes dans d’autres catégories (ex. "invariant_behaviors"), duplique-les dans "persistence_policy_behaviors" pour plus de clarté.

RÈGLE CRITIQUE ABSOLUE (ZÉRO ATTRIBUT FICTIF) :
- IMPORTANT : Ne crée JAMAIS de règles ni de méthodes demandant, filtrant, validant ou indexant des attributs INEXISTANTS dans le modèle !
- Appuie-toi EXCLUSIVEMENT sur la liste fermée « ATTRIBUTS AUTORISÉS DU MODÈLE » fournie dans le prompt. Tout attribut référencé dans "relatedAttributes", dans "rules" ou dans "associatedMethods" DOIT exister réellement dans le modèle.

Réponds EXCLUSIVEMENT en français pour "message", "askUser", "title", "description" et "rules", mais écris TOUTES les méthodes ("associatedMethods") EN ANGLAIS.
Renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON) en plaçant la clé "message" EN PREMIER :
{
  "message": "Synthèse claire en français des comportements et règles de la couche Domain proposés",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question métier ou d’architecture ?",
        "description": "Contexte court (optionnel)",
        "type": "single|multi|boolean|text",
        "options": ["Option A", "Option B"],
        "default": "Option A",
        "allowOther": true
      }
    ]
  },
  "specPatch": { ... }
}
Règles strictes :
- Si tu poses des questions via "askUser", mets "specPatch": null (ou ne renseigne que les faits certains) et fournis toujours "default".
- Lorsque l’action est claire, mets "askUser": null et fournis un "specPatch".
''';

  /// Guide statique décrivant le schéma JSON attendu dans `"specPatch"`.
  static const String patchSchemaGuide = '''
SCHÉMA "specPatch" POUR LA COUCHE DOMAIN (ARCHITECTURE HEXAGONALE) :
Chaque item des 7 sections comporte : "title" (FR), "description" (FR), "rules" (liste FR) et "associatedMethods" (liste de méthodes EN) :
{
  "invariant_behaviors": [
    {
      "id": "inv_existant (optionnel)",
      "code": "INV-01",
      "title": "Validation de l’intégrité de l’identité et du montant",
      "description": "Garantit la validité de l’identifiant et des montants financiers dès la création et à chaque mutation.",
      "rules": [
        "L’identifiant 'id' doit être un UUID valide.",
        "Le montant 'montantHt' doit être supérieur ou égal à 0."
      ],
      "associatedMethods": [
        "validateIdentity(id)",
        "validatePositiveAmountHt(montantHt)"
      ],
      "relatedAttributes": ["id", "montantHt"],
      "violationError": "InvalidOrderInvariantError"
    }
  ],
  "removeInvariants": ["id, code ou titre à supprimer"],
  "state_changing_behaviors": [
    {
      "id": "cmd_existant (optionnel)",
      "title": "Confirmation de la commande brouillon",
      "description": "Fige la commande et déclenche le processus d’exécution.",
      "rules": [
        "Règle de changement d’état : passage de BROUILLON vers CONFIRMEE uniquement si montantHt > 0.",
        "Émet l’événement OrderConfirmed après validation."
      ],
      "associatedMethods": [
        "confirmOrder()"
      ],
      "fromStates": ["BROUILLON"],
      "toState": "CONFIRMEE",
      "emittedEvents": ["OrderConfirmed"],
      "relatedAttributes": ["montantHt"]
    }
  ],
  "removeStateChanges": ["id, nom ou titre à supprimer"],
  "query_behaviors": [
    {
      "id": "qry_existant (optionnel)",
      "title": "Éligibilité à l’annulation et calculs dérivés",
      "description": "Expose l’état courant et les valeurs calculées sans effet de bord.",
      "rules": [
        "Une commande est annulable uniquement tant qu’elle est à l’état BROUILLON."
      ],
      "associatedMethods": [
        "canBeCancelled(): bool",
        "isDraft(): bool"
      ],
      "returnType": "bool",
      "relatedAttributes": []
    }
  ],
  "removeQueries": ["id, nom ou titre à supprimer"],
  "policy_service_behaviors": [
    {
      "id": "pol_existant (optionnel)",
      "title": "Politique de remise commerciale inter-agrégats",
      "description": "Applique les règles complexes de tarification entre la commande et le client.",
      "rules": [
        "Remise plafonnée selon l’encours du client collaborateur."
      ],
      "associatedMethods": [
        "applyCommercialDiscountPolicy(order: CommandeClient, client: Client): number"
      ],
      "collaborators": ["Client"],
      "relatedAttributes": ["montantHt"]
    }
  ],
  "removePolicyServices": ["id, nom ou titre à supprimer"],
  "factory_behaviors": [
    {
      "id": "fac_existant (optionnel)",
      "title": "Création et reconstitution d’une commande valide",
      "description": "Instancie une nouvelle entité valide ou la réhydrate depuis un snapshot.",
      "rules": [
        "Initialise l’état à BROUILLON et exécute tous les contrôles invariants.",
        "La reconstitution depuis snapshot restaure l’état sans émettre d’événement."
      ],
      "associatedMethods": [
        "createDraftOrder(montantHt: number): CommandeClient",
        "fromSnapshot(rawData)"
      ],
      "initialState": "BROUILLON",
      "relatedAttributes": ["montantHt"]
    }
  ],
  "removeFactories": ["id, nom ou titre à supprimer"],
  "domain_event_behaviors": [
    {
      "id": "evt_existant (optionnel)",
      "title": "Publication et écoute des événements de commande",
      "description": "Publie les faits métier immuables lors des transitions de la commande.",
      "rules": [
        "Publié immédiatement après la confirmation de la commande avec l’identifiant et le montant."
      ],
      "associatedMethods": [
        "publishOrderConfirmed(id, montantHt)"
      ],
      "trigger": "confirmOrder",
      "payloadFields": ["id: uuid", "montantHt: number"],
      "relatedAttributes": ["id", "montantHt"]
    }
  ],
  "removeDomainEvents": ["id, nom ou titre à supprimer"],
  "persistence_policy_behaviors": {
    "repositoryPortName": "CommandeClientRepository",
    "aggregateBoundary": "CommandeClient sauvegardée atomiquement",
    "concurrencyStrategy": "optimisticVersion|pessimisticLock|appendOnly|none",
    "deletionStrategy": "softDelete|hardDelete|immutableArchive",
    "consistencyNotes": "Transactions atomiques par agrégat.",
    "rules": [
      "Contrainte d’unicité stricte sur l’attribut 'id'.",
      "Index de recherche sur 'montantHt'."
    ],
    "portMethods": [
      {
        "id": "repm_existant (optionnel)",
        "category": "crud|verification|search|pagination|aggregate|transaction|statistics|batch|uniquenessRule|searchIndexRule|persistenceRule",
        "title": "Sauvegarde et chargement unitaire de la commande",
        "description": "Opérations CRUD métier de base sur l’agrégat.",
        "rules": [
          "Vérifie la version optimiste avant toute écriture."
        ],
        "associatedMethods": [
          "saveCommandeClient(order)",
          "findById(id)"
        ],
        "relatedAttributes": ["id"]
      },
      {
        "category": "uniquenessRule",
        "title": "Contrainte d’unicité sur l’identifiant",
        "description": "Garantit en base l’absence de doublon sur la clé métier ou technique.",
        "rules": [
          "Contrainte UNIQUE stricte sur 'id' (dupliquée depuis les invariants pour clarté)."
        ],
        "associatedMethods": [],
        "relatedAttributes": ["id"]
      },
      {
        "category": "searchIndexRule",
        "title": "Index de recherche sur le montant HT",
        "description": "Optimise les recherches et tris fréquents sur le montant.",
        "rules": [
          "Index B-Tree sur 'montantHt'."
        ],
        "associatedMethods": [],
        "relatedAttributes": ["montantHt"]
      }
    ],
    "removePortMethods": ["id, nom ou titre à supprimer"]
  }
}
''';

  /// Retourne l'ensemble ordonné des noms et chemins d'attributs existants dans [object].
  static List<String> allowedAttributePathsOf(BusinessObjectSpec object) {
    final paths = <String>[];
    void walk(List<BusinessAttribute> attrs, String prefix) {
      for (final attr in attrs) {
        final full = prefix.isEmpty ? attr.name : '$prefix.${attr.name}';
        paths.add(full);
        if (prefix.isNotEmpty && !paths.contains(attr.name)) {
          paths.add(attr.name);
        }
        if (attr.children.isNotEmpty) {
          walk(attr.children, full);
        }
      }
    }

    walk(object.attributes, '');
    return paths;
  }

  /// Construit le prompt complet d'un tour de chat pour la couche Domain de [entry].
  static String buildTurnPrompt({
    required String domainName,
    required DomainContracts contracts,
    required JsonNode entry,
    required DomainLayerTab activeTab,
    required List<SpecChatMessage> history,
    required String userInput,
    required BusinessObjectModelPreferences modelPreferences,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    CompanyGlossary? companyGlossary,
    int maxHistoryEntries = 10,
  }) {
    final details = contracts.details[entry.id] ?? ContractDetails.defaults;
    final object = contracts.objectFor(entry);
    final layer = contracts.domainLayerFor(entry);
    final allowedAttrs = allowedAttributePathsOf(object);
    final uniqueAttrs = <String>[];
    final indexedAttrs = <String>[];
    void collectPersistenceHints(List<BusinessAttribute> attrs, String prefix) {
      for (final attr in attrs) {
        final full = prefix.isEmpty ? attr.name : '$prefix.${attr.name}';
        if (attr.unique) uniqueAttrs.add(full);
        if (attr.schemaConstraints.xSearchable == true ||
            attr.schemaConstraints.xDatabaseIndex == true) {
          indexedAttrs.add(full);
        }
        if (attr.children.isNotEmpty) {
          collectPersistenceHints(attr.children, full);
        }
      }
    }

    collectPersistenceHints(object.attributes, '');

    final objectSnapshot = const JsonEncoder.withIndent('  ').convert({
      'name': object.name,
      'technicalName': object.technicalName,
      'aggregateRoot': object.aggregateRoot,
      'description': object.description,
      'attributes': [for (final a in object.attributes) a.toJson()],
      if (object.lifecycleStates.isNotEmpty)
        'lifecycleStates': [for (final s in object.lifecycleStates) s.toJson()],
      if (object.lifecycleTransitions.isNotEmpty)
        'lifecycleTransitions': [
          for (final t in object.lifecycleTransitions) t.toJson(),
        ],
    });
    final layerSnapshot = const JsonEncoder.withIndent('  ').convert(
      layer.toJson(),
    );
    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');
    final targets = contracts.referenceTargetsOf(entry);

    final buf = StringBuffer()
      ..writeln(
        'CONTEXTE : COUCHE DOMAIN (ARCHITECTURE HEXAGONALE) DU MODÈLE '
        '« ${object.technicalName} » DANS LE DOMAINE « $domainName »',
      )
      ..writeln(
        SpecPromptBuilder.questioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      )
      ..writeln()
      ..writeln(modelPreferences.toPromptDirective());

    final glossaryBlock = SpecPromptBuilder.companyGlossaryBlock(
      companyGlossary,
    );
    if (glossaryBlock.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(glossaryBlock);
    }

    buf
      ..writeln()
      ..writeln('MODÈLE CIBLE :')
      ..writeln('- id : ${entry.id}')
      ..writeln('- nom technique : ${object.technicalName}')
      ..writeln('- type DSL : ${entry.type}')
      ..writeln('- rubrique : ${entry.parent?.name ?? ''}')
      ..writeln(
        '- titre métier : ${details.title.isEmpty ? object.name : details.title}',
      )
      ..writeln('- version : ${details.version}')
      ..writeln(
        '- ONGLET ACTIF CONSULTÉ PAR L’UTILISATEUR : '
        '${activeTab.label} (${activeTab.subtitle})',
      )
      ..writeln()
      ..writeln(
        'ATTRIBUTS AUTORISÉS DU MODÈLE '
        '(LISTE FERMÉE — INTERDICTION D’UTILISER UN ATTRIBUT NON LISTÉ ICI) :',
      );
    if (allowedAttrs.isEmpty) {
      buf.writeln(
        'AUCUN ATTRIBUT DÉCLARÉ SUR CE MODÈLE. '
        'Ne crée aucune règle ni méthode supposant des attributs inexistants '
        '(seul fromSnapshot(rawData) ou une question askUser est possible).',
      );
    } else {
      buf.writeln('- Attributs existants : ${allowedAttrs.join(', ')}');
      if (uniqueAttrs.isNotEmpty) {
        buf.writeln(
          '- Attributs marqués unique=true (à expliciter dans les rules de persistence_policy_behaviors) : '
          '${uniqueAttrs.join(', ')}',
        );
      }
      if (indexedAttrs.isNotEmpty) {
        buf.writeln(
          '- Attributs marqués x-searchable / x-database-index (à expliciter dans les rules d’index de persistence_policy_behaviors) : '
          '${indexedAttrs.join(', ')}',
        );
      }
    }

    buf
      ..writeln()
      ..writeln('STRUCTURE ET ATTRIBUTS DU MODÈLE (JSON) :')
      ..writeln(objectSnapshot)
      ..writeln()
      ..writeln('AUTRES ENTRÉES DU DOMAINE (COLLABORATEURS / EVENTS / DTO) :');
    if (targets.isEmpty) {
      buf.writeln('(aucune autre entrée dans ce domaine)');
    } else {
      for (final MapEntry(key: id, value: name) in targets.entries) {
        final other = contracts.entryById(id);
        if (other == null) continue;
        final title = contracts.details[id]?.title ?? '';
        buf.writeln(
          '- nom technique : $name · type : ${other.type}'
          ' · rubrique : ${other.parent?.name ?? ''}'
          '${title.isEmpty ? '' : ' · titre : $title'}',
        );
      }
    }

    buf
      ..writeln()
      ..writeln('ÉTAT ACTUEL DE LA COUCHE DOMAIN (7 ONGLETS, JSON) :')
      ..writeln(layerSnapshot);

    if (historyText.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT :')
        ..writeln(historyText);
    }

    buf
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR :')
      ..writeln(userInput.trim());

    return buf.toString();
  }

  /// Fusionne un `"specPatch"` IA avec [current] de manière immuable et retourne
  /// la nouvelle spécification ainsi qu'un résumé lisible des changements.
  ///
  /// Lorsque [modelObject] est fourni, vérifie qu'aucun `relatedAttributes` ne
  /// référence un attribut inexistant dans [modelObject].
  static ({HexagonalDomainLayerSpec layer, String summary}) applyPatch(
    HexagonalDomainLayerSpec current,
    Map<String, Object?> patch, {
    BusinessObjectSpec? modelObject,
  }) {
    final allowedDisplay = modelObject == null
        ? null
        : allowedAttributePathsOf(modelObject);
    final allowedLower = allowedDisplay == null
        ? null
        : <String>{for (final p in allowedDisplay) p.toLowerCase()};

    void checkRelatedAttributes(List<String> attrs, String contextLabel) {
      if (allowedLower == null || attrs.isEmpty) return;
      for (final rawAttr in attrs) {
        final clean = rawAttr.split(':').first.trim();
        if (clean.isEmpty) continue;
        if (!allowedLower.contains(clean.toLowerCase())) {
          final allowedHint = allowedDisplay!.isEmpty
              ? 'aucun attribut défini sur ce modèle'
              : allowedDisplay.join(', ');
          throw FormatException(
            'Attribut inexistant « $clean » référencé dans « $contextLabel » : '
            'seuls les attributs existants du modèle ($allowedHint) sont autorisés.',
          );
        }
      }
    }

    final summaryParts = <String>[];

    final invOutcome = _mergeSection<DomainInvariantSpec>(
      existing: current.invariants,
      rawItems: patch['invariant_behaviors'] ?? patch['invariants'],
      rawRemovals:
          patch['remove_invariant_behaviors'] ?? patch['removeInvariants'],
      parseItem: (raw) {
        final item = DomainInvariantSpec.fromJson(raw);
        checkRelatedAttributes(item.relatedAttributes, item.title);
        return item;
      },
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.code, e.methodSignature, e.title],
      idPrefix: 'inv',
    );
    _appendDiffSummary(summaryParts, 'invariant(s)', invOutcome);

    final cmdOutcome = _mergeSection<DomainStateChangeSpec>(
      existing: current.stateChanges,
      rawItems: patch['state_changing_behaviors'] ?? patch['stateChanges'],
      rawRemovals:
          patch['remove_state_changing_behaviors'] ??
          patch['removeStateChanges'],
      parseItem: (raw) {
        final item = DomainStateChangeSpec.fromJson(raw);
        checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
        return item;
      },
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name, e.methodSignature, e.title],
      idPrefix: 'cmd',
    );
    _appendDiffSummary(summaryParts, 'commande(s)', cmdOutcome);

    final qryOutcome = _mergeSection<DomainQuerySpec>(
      existing: current.queries,
      rawItems: patch['query_behaviors'] ?? patch['queries'],
      rawRemovals: patch['remove_query_behaviors'] ?? patch['removeQueries'],
      parseItem: (raw) {
        final item = DomainQuerySpec.fromJson(raw);
        checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
        return item;
      },
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name, e.methodSignature, e.title],
      idPrefix: 'qry',
    );
    _appendDiffSummary(summaryParts, 'query(ies)', qryOutcome);

    final polOutcome = _mergeSection<DomainPolicyServiceSpec>(
      existing: current.policyServices,
      rawItems: patch['policy_service_behaviors'] ?? patch['policyServices'],
      rawRemovals:
          patch['remove_policy_service_behaviors'] ??
          patch['removePolicyServices'],
      parseItem: (raw) {
        final item = DomainPolicyServiceSpec.fromJson(raw);
        checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
        return item;
      },
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name, e.methodSignature, e.title],
      idPrefix: 'pol',
    );
    _appendDiffSummary(summaryParts, 'policy(ies)', polOutcome);

    final facOutcome = _mergeSection<DomainFactorySpec>(
      existing: current.factories,
      rawItems: patch['factory_behaviors'] ?? patch['factories'],
      rawRemovals:
          patch['remove_factory_behaviors'] ?? patch['removeFactories'],
      parseItem: (raw) {
        final item = DomainFactorySpec.fromJson(raw);
        checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
        return item;
      },
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name, e.methodSignature, e.title],
      idPrefix: 'fac',
    );
    _appendDiffSummary(summaryParts, 'factory(ies)', facOutcome);

    final evtOutcome = _mergeSection<DomainEventSpec>(
      existing: current.domainEvents,
      rawItems: patch['domain_event_behaviors'] ?? patch['domainEvents'],
      rawRemovals:
          patch['remove_domain_event_behaviors'] ?? patch['removeDomainEvents'],
      parseItem: (raw) {
        final item = DomainEventSpec.fromJson(raw);
        checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
        return item;
      },
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name, e.methodSignature, e.title],
      idPrefix: 'evt',
    );
    _appendDiffSummary(summaryParts, 'event(s)', evtOutcome);

    var nextPersistence = current.persistencePolicy;
    final rawPersistencePatch =
        patch['persistence_policy_behaviors'] ?? patch['persistencePolicy'];
    if (rawPersistencePatch is List) {
      final methodsOutcome = _mergeSection<DomainRepositoryMethodSpec>(
        existing: current.persistencePolicy.portMethods,
        rawItems: rawPersistencePatch,
        rawRemovals:
            patch['remove_persistence_policy_behaviors'] ??
            patch['removePortMethods'],
        parseItem: (raw) {
          final item = DomainRepositoryMethodSpec.fromJson(raw);
          checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
          return item;
        },
        idOf: (e) => e.id,
        withId: (e, id) => e.copyWith(id: id),
        naturalKeysOf: (e) => e.naturalMergeKeys,
        idPrefix: 'repm',
      );
      final candidate = current.persistencePolicy.copyWith(
        portMethods: methodsOutcome.items,
      );
      if (candidate != current.persistencePolicy) {
        nextPersistence = candidate;
        summaryParts.add('persistence policy');
      }
    } else if (rawPersistencePatch case final Map rawPolicy) {
      final methodsOutcome = _mergeSection<DomainRepositoryMethodSpec>(
        existing: current.persistencePolicy.portMethods,
        rawItems:
            rawPolicy['portMethods'] ??
            rawPolicy['behaviors'] ??
            rawPolicy['items'],
        rawRemovals:
            rawPolicy['removePortMethods'] ??
            patch['remove_persistence_policy_behaviors'],
        parseItem: (raw) {
          final item = DomainRepositoryMethodSpec.fromJson(raw);
          checkRelatedAttributes(item.relatedAttributes, item.effectiveTitle);
          return item;
        },
        idOf: (e) => e.id,
        withId: (e, id) => e.copyWith(id: id),
        naturalKeysOf: (e) => e.naturalMergeKeys,
        idPrefix: 'repm',
      );
      final mergedRules = <String>[...current.persistencePolicy.rules];
      if (rawPolicy['rules'] case final List incomingRules) {
        for (final r in incomingRules) {
          final text = '$r'.trim();
          if (text.isNotEmpty &&
              !mergedRules.any((x) => x.toLowerCase() == text.toLowerCase())) {
            mergedRules.add(text);
          }
        }
      }
      if (rawPolicy['removeRules'] case final List removedRules) {
        final removeSet = {
          for (final r in removedRules) '$r'.trim().toLowerCase(),
        };
        mergedRules.removeWhere((x) => removeSet.contains(x.toLowerCase()));
      }
      final candidate = DomainPersistencePolicySpec(
        repositoryPortName: rawPolicy['repositoryPortName'] is String
            ? (rawPolicy['repositoryPortName'] as String).trim()
            : current.persistencePolicy.repositoryPortName,
        aggregateBoundary: rawPolicy['aggregateBoundary'] is String
            ? (rawPolicy['aggregateBoundary'] as String).trim()
            : current.persistencePolicy.aggregateBoundary,
        concurrencyStrategy: rawPolicy.containsKey('concurrencyStrategy')
            ? DomainConcurrencyStrategy.fromJson(
                rawPolicy['concurrencyStrategy'],
              )
            : current.persistencePolicy.concurrencyStrategy,
        deletionStrategy: rawPolicy.containsKey('deletionStrategy')
            ? DomainDeletionStrategy.fromJson(rawPolicy['deletionStrategy'])
            : current.persistencePolicy.deletionStrategy,
        consistencyNotes: rawPolicy['consistencyNotes'] is String
            ? (rawPolicy['consistencyNotes'] as String).trim()
            : current.persistencePolicy.consistencyNotes,
        rules: mergedRules,
        portMethods: methodsOutcome.items,
      );
      if (candidate != current.persistencePolicy) {
        nextPersistence = candidate;
        summaryParts.add('persistence policy');
      }
    }

    final nextLayer = HexagonalDomainLayerSpec(
      invariants: invOutcome.items,
      stateChanges: cmdOutcome.items,
      queries: qryOutcome.items,
      policyServices: polOutcome.items,
      factories: facOutcome.items,
      domainEvents: evtOutcome.items,
      persistencePolicy: nextPersistence,
    );
    nextLayer.validate();

    return (
      layer: nextLayer,
      summary: summaryParts.isEmpty
          ? ''
          : 'Couche Domain mise à jour (${summaryParts.join(', ')})',
    );
  }

  static void _appendDiffSummary<T>(
    List<String> parts,
    String label,
    ({List<T> items, int added, int updated, int removed}) outcome,
  ) {
    if (outcome.added > 0) parts.add('+${outcome.added} $label');
    if (outcome.updated > 0) parts.add('~${outcome.updated} $label');
    if (outcome.removed > 0) parts.add('-${outcome.removed} $label');
  }

  static ({List<T> items, int added, int updated, int removed}) _mergeSection<T>({
    required List<T> existing,
    required Object? rawItems,
    required Object? rawRemovals,
    required T Function(Object?) parseItem,
    required String Function(T) idOf,
    required T Function(T, String) withId,
    required List<String> Function(T) naturalKeysOf,
    required String idPrefix,
  }) {
    final removeKeys = <String>{
      if (rawRemovals case final List list)
        for (final entry in list)
          if (entry is String && entry.trim().isNotEmpty)
            entry.trim().toLowerCase(),
    };

    bool shouldRemove(T item) {
      if (removeKeys.contains(idOf(item).toLowerCase())) return true;
      for (final key in naturalKeysOf(item)) {
        if (key.trim().isNotEmpty &&
            removeKeys.contains(key.trim().toLowerCase())) {
          return true;
        }
      }
      return false;
    }

    final merged = <T>[
      for (final item in existing)
        if (!shouldRemove(item)) item,
    ];
    final removed = existing.length - merged.length;
    var added = 0;
    var updated = 0;

    if (rawItems case final List incomingList) {
      for (final raw in incomingList) {
        final parsed = parseItem(raw);
        final explicitId = raw is Map &&
            raw['id'] is String &&
            (raw['id'] as String).trim().isNotEmpty;
        var index = explicitId
            ? merged.indexWhere((e) => idOf(e) == idOf(parsed))
            : -1;
        if (index < 0) {
          final candidateKeys = {
            for (final k in naturalKeysOf(parsed))
              if (k.trim().isNotEmpty) k.trim().toLowerCase(),
          };
          if (candidateKeys.isNotEmpty) {
            index = merged.indexWhere(
              (e) => naturalKeysOf(e).any(
                (k) => candidateKeys.contains(k.trim().toLowerCase()),
              ),
            );
          }
        }
        if (index >= 0) {
          final aligned = withId(parsed, idOf(merged[index]));
          if (merged[index] != aligned) {
            merged[index] = aligned;
            updated++;
          }
        } else {
          final idTaken = merged.any((e) => idOf(e) == idOf(parsed));
          merged.add(
            explicitId && !idTaken
                ? parsed
                : withId(parsed, '${idPrefix}_${shortid.generate()}'),
          );
          added++;
        }
      }
    }

    return (items: merged, added: added, updated: updated, removed: removed);
  }
}
