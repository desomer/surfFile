/// Agent IA spécialisé pour la conception de la couche Domain en Architecture
/// Hexagonale ([DomainLayerAiAgent]) d'un objet métier côté Design.
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
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
- Zéro dépendance technique ou framework dans le Domain (pas d’annotations ORM, HTTP ou SQL dans la logique métier).
- Protection systématique des invariants dès l’instanciation (Factory) et lors de chaque mutation d’état (State changing).
- Séparation claire entre commandes à effets de bord (State changing, qui vérifient les préconditions, mutent l’état et émettent des Domain events) et lectures/calculs purs (Query, sans aucun effet de bord).
- Extraction des règles transverses ou multi-entités dans des Policy Services sans état.
- Contrat explicite du port sortant de persistance (Persistence policy / Repository interface) côté Domain.

Tu pilotes les 7 sections suivantes de la couche Domain de l’objet :
1. "invariants" (onglet Invariants) : règles d’intégrité garanties à tout instant (code, titre, expression logique, attributs concernés, erreur métier levée).
2. "stateChanges" (onglet State changing) : commandes et méthodes métier modifiant l’état interne (nom, paramètres, préconditions, mutations, états source/cible, événements émis, erreurs métier).
3. "queries" (onglet Query) : méthodes pures, calculs dérivés et prédicats sans effet de bord (nom, paramètres, type de retour, formule/logique).
4. "policyServices" (onglet Policy Services) : politiques et services du domaine sans état collaborant avec cet objet (nom, opération, collaborateurs, règles de décision).
5. "factories" (onglet Factory) : fabriques d’instanciation ou de reconstitution garantissant un état initial valide (nom, paramètres, état initial, invariants vérifiés, événements émis).
6. "domainEvents" (onglet Domain events) : faits métier immuables nommés au passé émis par l’objet (nom, déclencheur, champs du payload, référence éventuelle vers une entrée eventxpayloaddto du domaine).
7. "persistencePolicy" (onglet Persistence policy) : contrat du port sortant Repository, frontière transactionnelle de l’agrégat, stratégie de concurrence, stratégie de suppression/archivage et méthodes du port.

Cohérence inter-onglets attendue :
- Lorsqu’une commande "stateChanges" ou une "factory" émet un événement métier, déclare ou mets à jour l’événement correspondant dans "domainEvents".
- Appuie les expressions, paramètres et payloads sur les attributs réels du modèle fournis dans le contexte.
- Tiens compte de l’onglet actif consulté par l’utilisateur, tout en pouvant compléter plusieurs onglets d’un seul coup lorsque la demande est transverse.
- En cas d’ambiguïté métier structurante (règle de gestion, concurrence, suppression logique vs archivage légal), utilise "askUser" avec des valeurs "default" pertinentes.

Réponds EXCLUSIVEMENT en français et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON).
Place impérativement la clé "message" EN PREMIER pour permettre le streaming en direct :
{
  "message": "Synthèse claire en français des éléments de la couche Domain proposés ou mis à jour",
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
Toutes les clés sont optionnelles ; seuls les éléments listés sont ajoutés, mis à jour (par "id", sinon par "code"/"name") ou supprimés :
{
  "invariants": [
    {
      "id": "inv_existant (optionnel)",
      "code": "INV-01",
      "title": "Montant HT positif",
      "expression": "montantHt >= 0",
      "relatedAttributes": ["montantHt"],
      "violationError": "MontantNegatifInterdit",
      "description": "Un montant hors taxe ne peut jamais être négatif."
    }
  ],
  "removeInvariants": ["id ou code à supprimer"],
  "stateChanges": [
    {
      "id": "cmd_existant (optionnel)",
      "name": "confirmer",
      "parameters": ["dateConfirmation: datetime"],
      "preconditions": ["statut == BROUILLON", "lignes non vides"],
      "mutations": ["statut = CONFIRMEE", "confirmeeLe = dateConfirmation"],
      "fromStates": ["BROUILLON"],
      "toState": "CONFIRMEE",
      "emittedEvents": ["CommandeConfirmee"],
      "domainErrors": ["CommandeDejaConfirmee", "CommandeVide"],
      "description": "Valide définitivement la commande et fige ses lignes."
    }
  ],
  "removeStateChanges": ["id ou nom à supprimer"],
  "queries": [
    {
      "id": "qry_existant (optionnel)",
      "name": "estAnnulable",
      "parameters": [],
      "returnType": "bool",
      "formula": "statut == BROUILLON || statut == CONFIRMEE",
      "description": "Indique si la commande peut encore être annulée sans avoir."
    }
  ],
  "removeQueries": ["id ou nom à supprimer"],
  "policyServices": [
    {
      "id": "pol_existant (optionnel)",
      "name": "PolitiqueRemiseCommerciale",
      "operation": "calculerRemise(commande: CommandeClient, palierClient: string) -> number",
      "collaborators": ["Client"],
      "rules": ["Plafond de remise 15% sans validation direction"],
      "description": "Calcule le taux de remise applicable selon le profil client."
    }
  ],
  "removePolicyServices": ["id ou nom à supprimer"],
  "factories": [
    {
      "id": "fac_existant (optionnel)",
      "name": "creerBrouillon",
      "parameters": ["clientId: uuid", "devise: string"],
      "initialState": "BROUILLON",
      "enforcedInvariants": ["INV-01"],
      "emittedEvents": ["CommandeBrouillonCreee"],
      "description": "Instancie une nouvelle commande vierge à l’état brouillon."
    }
  ],
  "removeFactories": ["id ou nom à supprimer"],
  "domainEvents": [
    {
      "id": "evt_existant (optionnel)",
      "name": "CommandeConfirmee",
      "trigger": "confirmer",
      "payloadFields": ["commandeId: uuid", "montantHt: number", "confirmeeLe: datetime"],
      "contractEntryRef": "nom technique éventuel d’une entrée eventxpayloaddto du domaine",
      "description": "Publié lorsqu’une commande passe à l’état confirmé."
    }
  ],
  "removeDomainEvents": ["id ou nom à supprimer"],
  "persistencePolicy": {
    "repositoryPortName": "CommandeClientRepository",
    "aggregateBoundary": "CommandeClient et ses sous-objets internes sauvegardés atomiquement",
    "concurrencyStrategy": "optimisticVersion|pessimisticLock|appendOnly|none",
    "deletionStrategy": "softDelete|hardDelete|immutableArchive",
    "consistencyNotes": "Unicité sur numeroCommande ; conservation légale 10 ans.",
    "portMethods": [
      {
        "id": "repm_existant (optionnel)",
        "name": "findById",
        "signature": "(id: uuid) -> CommandeClient?",
        "description": "Charge l’agrégat complet par son identifiant."
      },
      {
        "name": "save",
        "signature": "(commande: CommandeClient) -> void",
        "description": "Persiste atomiquement l’agrégat avec contrôle de version optimiste."
      }
    ],
    "removePortMethods": ["id ou nom à supprimer"]
  }
}
''';

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
  static ({HexagonalDomainLayerSpec layer, String summary}) applyPatch(
    HexagonalDomainLayerSpec current,
    Map<String, Object?> patch,
  ) {
    final summaryParts = <String>[];

    final invOutcome = _mergeSection<DomainInvariantSpec>(
      existing: current.invariants,
      rawItems: patch['invariants'],
      rawRemovals: patch['removeInvariants'],
      parseItem: DomainInvariantSpec.fromJson,
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.code, e.title],
      idPrefix: 'inv',
    );
    _appendDiffSummary(summaryParts, 'invariant(s)', invOutcome);

    final cmdOutcome = _mergeSection<DomainStateChangeSpec>(
      existing: current.stateChanges,
      rawItems: patch['stateChanges'],
      rawRemovals: patch['removeStateChanges'],
      parseItem: DomainStateChangeSpec.fromJson,
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name],
      idPrefix: 'cmd',
    );
    _appendDiffSummary(summaryParts, 'commande(s)', cmdOutcome);

    final qryOutcome = _mergeSection<DomainQuerySpec>(
      existing: current.queries,
      rawItems: patch['queries'],
      rawRemovals: patch['removeQueries'],
      parseItem: DomainQuerySpec.fromJson,
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name],
      idPrefix: 'qry',
    );
    _appendDiffSummary(summaryParts, 'query(ies)', qryOutcome);

    final polOutcome = _mergeSection<DomainPolicyServiceSpec>(
      existing: current.policyServices,
      rawItems: patch['policyServices'],
      rawRemovals: patch['removePolicyServices'],
      parseItem: DomainPolicyServiceSpec.fromJson,
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name],
      idPrefix: 'pol',
    );
    _appendDiffSummary(summaryParts, 'policy(ies)', polOutcome);

    final facOutcome = _mergeSection<DomainFactorySpec>(
      existing: current.factories,
      rawItems: patch['factories'],
      rawRemovals: patch['removeFactories'],
      parseItem: DomainFactorySpec.fromJson,
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name],
      idPrefix: 'fac',
    );
    _appendDiffSummary(summaryParts, 'factory(ies)', facOutcome);

    final evtOutcome = _mergeSection<DomainEventSpec>(
      existing: current.domainEvents,
      rawItems: patch['domainEvents'],
      rawRemovals: patch['removeDomainEvents'],
      parseItem: DomainEventSpec.fromJson,
      idOf: (e) => e.id,
      withId: (e, id) => e.copyWith(id: id),
      naturalKeysOf: (e) => <String>[e.name],
      idPrefix: 'evt',
    );
    _appendDiffSummary(summaryParts, 'event(s)', evtOutcome);

    var nextPersistence = current.persistencePolicy;
    if (patch['persistencePolicy'] case final Map rawPolicy) {
      final methodsOutcome = _mergeSection<DomainRepositoryMethodSpec>(
        existing: current.persistencePolicy.portMethods,
        rawItems: rawPolicy['portMethods'],
        rawRemovals: rawPolicy['removePortMethods'],
        parseItem: DomainRepositoryMethodSpec.fromJson,
        idOf: (e) => e.id,
        withId: (e, id) => e.copyWith(id: id),
        naturalKeysOf: (e) => <String>[e.name],
        idPrefix: 'repm',
      );
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
