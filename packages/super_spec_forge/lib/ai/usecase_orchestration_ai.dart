/// Agent IA spécialisé pour la conception de la couche applicative « Cas d’usage
/// & orchestration » ([UseCaseOrchestrationAiAgent]) : cartographie CQRS par
/// Bounded Context, Use Cases détaillés (10 sections + Given/When/Then) et
/// Sagas Mermaid avec matrice de compensations.
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/company_glossary.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import '../models/usecase_orchestration_spec.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';

/// Orchestre les instructions système, la construction du contexte projet/domaine
/// et la fusion des patches JSON pour la page « Cas d’usage & orchestration ».
abstract final class UseCaseOrchestrationAiAgent {
  /// Outils d'inspection en lecture seule du projet Spec actif.
  static const Set<String> toolNames = <String>{
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'get_event_storming',
    'inspect_business_object',
    'get_example_mapping',
    'get_business_rules',
    'get_debug_entries',
  };

  /// Guide statique combinant le schéma `"specPatch"` et le guide des outils.
  static String get staticGuide =>
      '$patchSchemaGuide\n\n---\n\n${SpecForgeToolRegistry.toolsGuide(toolNames: toolNames)}';

  /// Instruction système de l'Architecte Couche Applicative (DDD / CQRS / Saga).
  static const String systemInstruction = '''
Tu es un expert en Architecture Hexagonale, Domain-Driven Design (DDD), CQRS et Saga.
À partir des cas d’usage, exigences, règles de gestion, Event Storming, modèles et couches Domain du projet et du domaine en cours, tu conçois :
1. La **cartographie des Use Cases et des Sagas** de la couche applicative par Bounded Context (`cartography`).
2. La **spécification détaillée des Use Cases** applicatifs (`useCases`), structurée en 10 sections + métadonnées CQRS/Hexa.
3. La **spécification des Sagas distribuées** (`sagas`) avec diagramme Mermaid et matrice des compensations.

RÈGLES D’ARCHITECTURE OBLIGATOIRES :
- **Qualification CQRS explicite** (`cqrsType`: `command` ou `query`) :
  - Une `command` charge un unique agrégat cible (`targetAggregate`), vérifie les règles/invariants du Domain Layer, persiste via un port Repository et publie des Domain/Integration Events (`emittedEvents`).
  - Une `query` ne modifie aucun état et lit directement un Read Model ou une projection via un port de lecture dédié.
- **Frontière transactionnelle** : un Use Case = une transaction atomique sur un seul Agrégat. Dès qu’une opération coordonne plusieurs Agrégats ou plusieurs Bounded Contexts, modélise une **Saga** (`sagas`) en plus des Use Cases unitaires.
- **Ports Entrants vs Ports Sortants** : sépare explicitement le port entrant (`inboundPort`, ex. `UpdateProductPriceUseCase`) et les ports sortants (`outboundPorts` : Repositories, services externes, bus d’événements, horloge/générateur d’ID). Réutilise prioritairement les noms de modèles, méthodes Domain et `repositoryPortName` déjà définis dans le domaine.
- **Traçabilité & Concurrence** : renseigne `linkedSpecRefs` (`EXF-xxx`, `RG-xxx`, `UC-xxx`) et `concurrencyAndIdempotency` (verrou optimiste / clé d’idempotence) lorsque pertinent.
- **10 SECTIONS OBLIGATOIRES POUR CHAQUE USE CASE** :
  1. `businessGoal` : Objectif métier clair en français.
  2. `triggerInputs` : Paramètres d’entrée typés et contraints (`name`, `type`, `constraints`, `description`).
  3. `businessRules` : Règles métier vérifiées (en citant les `RG-xxx` existantes si présentes).
  4. `inboundPort` + `outboundPorts` + `emittedEvents` : Ports entrant/sortants et événements publiés.
  5. `detailedProcess` : Étapes ordonnées et numérotables de la couche applicative.
  6. `outputs` : Champs de sortie retournés (`name`, `type`, `constraints`, `description`).
  7. `possibleErrors` : Erreurs métier/applicatives explicites (ex. `ProductNotFound`, `UnauthorizedUser`, `InvalidPrice`, `RepositoryError`).
  8. `scenarios` : Au moins un scénario nominal et les scénarios d’erreur clés au format strict `Given / When / Then`.
  9. `acceptanceCriteria` : Critères d’acceptation vérifiables.
  10. `nonGoals` : Ce que le Use Case ne couvre explicitement pas (hors périmètre).
- **SPÉCIFICATION DES SAGAS** :
  - `coordinationMode` (`orchestration` ou `choreography`), `triggerEventOrCommand`, `correlationKey` (clé de corrélation/idempotence) et `failureRecoveryStrategy` (reprise, DLQ, alerte manuelle si compensation critique).
  - `mermaidDiagram` : diagramme Mermaid complet (`sequenceDiagram` ou `stateDiagram-v2`) couvrant à la fois le flux nominal ET la branche de compensation.
  - `compensationMatrix` : matrice complète à 8 champs par étape (`step`, `nominalAction`, `compensationAction`, `rollbackTrigger`, `criticality` (`critical|high|medium|low`), `idempotent`, `retryable`, `timeout`).

EXEMPLE DE RÉFÉRENCE (Use Case `UpdateProductPrice`) :
- Objectif métier : Permettre la mise à jour du prix d’un produit existant.
- Déclencheur (Input) : `productId: string (UUID)`, `newPrice: number (> 0)`, `updatedBy: string (userId)`.
- Règles métier : Produit existant, prix > 0, historisation, autorisation utilisateur.
- Ports : `ProductRepository`, `PriceHistoryRepository`, `UserAuthorizationService`.
- Processus : Charger -> Vérifier droits -> `product.updatePrice(newPrice)` -> Sauvegarder -> Enregistrer historique -> Retourner mise à jour.
- Sortie : `productId`, `oldPrice`, `newPrice`, `updatedAt`, `updatedBy`.
- Erreurs : `ProductNotFound`, `UnauthorizedUser`, `InvalidPrice`, `RepositoryError`.
- Scénarios Given/When/Then : nominal + erreurs (introuvable, prix invalide).
- Critères d'acceptation & Non-objectifs exhaustifs.

Réponds EXCLUSIVEMENT en français pour les textes métier (`message`, `askUser`, `title`, `businessGoal`, `businessRules`, `detailedProcess`, `scenarios`, `acceptanceCriteria`, `nonGoals`, `description`, `notes`, etc.) et utilise des identifiants techniques clairs en anglais pour les noms de Use Cases, Sagas, ports, événements et erreurs (`UpdateProductPrice`, `OrderFulfillmentSaga`, `ProductRepository`, `ProductNotFound`).
Renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON) en plaçant la clé `"message"` EN PREMIER :
{
  "message": "Synthèse claire en français des cartographies, Use Cases et Sagas proposés",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question d’architecture applicative ?",
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
- Si tu poses des questions via `"askUser"`, mets `"specPatch": null` (ou ne renseigne que les faits certains) et fournis toujours `"default"`.
- Lorsque l’action est claire, mets `"askUser": null` et fournis un `"specPatch"`.
''';

  /// Guide statique décrivant le schéma JSON attendu dans `"specPatch"`.
  static const String patchSchemaGuide = '''
SCHÉMA "specPatch" POUR « CAS D’USAGE & ORCHESTRATION » :
{
  "cartography": [
    {
      "id": "bcmap_existant (optionnel)",
      "boundedContext": "Catalogue Produits",
      "description": "Gestion du cycle de vie et de la tarification des produits.",
      "useCaseCodes": ["UC-001", "UC-002"],
      "sagaCodes": ["SAGA-001"],
      "notes": "Publie les événements de prix vers Facturation et Commande."
    }
  ],
  "removeCartography": ["id ou nom du Bounded Context à supprimer"],
  "useCases": [
    {
      "id": "uc_existant (optionnel)",
      "code": "UC-001",
      "name": "UpdateProductPrice",
      "title": "Mise à jour du prix d’un produit",
      "boundedContext": "Catalogue Produits",
      "cqrsType": "command|query",
      "targetAggregate": "Product",
      "businessGoal": "Permettre la mise à jour du prix d’un produit existant.",
      "triggerInputs": [
        { "name": "productId", "type": "uuid", "required": true, "constraints": "UUID, requis", "description": "Identifiant du produit" },
        { "name": "newPrice", "type": "number", "required": true, "constraints": "> 0", "description": "Nouveau tarif" },
        { "name": "metadata", "type": "object", "required": false, "children": [{ "name": "reason", "type": "string", "required": false }] }
      ],
      "businessRules": [
        "Le produit doit exister.",
        "Le prix doit être strictement positif."
      ],
      "inboundPort": "UpdateProductPriceUseCase",
      "outboundPorts": ["ProductRepository", "PriceHistoryRepository", "UserAuthorizationService"],
      "emittedEvents": ["ProductPriceUpdated"],
      "detailedProcess": [
        "Charger le produit via ProductRepository.findById",
        "Vérifier les droits via UserAuthorizationService.canUpdatePrice",
        "Appeler product.updatePrice(newPrice)",
        "Sauvegarder via ProductRepository.save",
        "Enregistrer l’historique via PriceHistoryRepository.recordChange",
        "Retourner les informations de mise à jour"
      ],
      "outputs": [
        { "name": "productId", "type": "string", "constraints": "UUID", "description": "" },
        { "name": "oldPrice", "type": "number", "constraints": "", "description": "" },
        { "name": "newPrice", "type": "number", "constraints": "", "description": "" }
      ],
      "possibleErrors": ["ProductNotFound", "UnauthorizedUser", "InvalidPrice", "RepositoryError"],
      "scenarios": [
        {
          "id": "scn_existant (optionnel)",
          "name": "Scénario nominal : Mise à jour réussie du prix",
          "isNominal": true,
          "given": ["un produit existe avec l'identifiant product-123", "son prix actuel est de 100.00"],
          "when": ["l'utilisateur demande la mise à jour du prix à 120.00"],
          "then": ["le prix du produit est mis à jour à 120.00", "le produit est sauvegardé"]
        }
      ],
      "acceptanceCriteria": ["Le système doit permettre la mise à jour du prix d'un produit existant."],
      "nonGoals": ["La création d'un produit.", "La gestion des devises."],
      "concurrencyAndIdempotency": "Verrou optimiste sur version de l’agrégat Product.",
      "linkedSpecRefs": ["EXF-001", "RG-003"]
    }
  ],
  "removeUseCases": ["id, code ou nom du Use Case à supprimer"],
  "sagas": [
    {
      "id": "saga_existant (optionnel)",
      "code": "SAGA-001",
      "name": "OrderFulfillmentSaga",
      "title": "Orchestration de validation et paiement de commande",
      "boundedContexts": ["Commandes", "Stock", "Paiement"],
      "coordinationMode": "orchestration|choreography",
      "triggerEventOrCommand": "PlaceOrderCommand",
      "correlationKey": "orderId",
      "failureRecoveryStrategy": "Retry exponentiel (3x) sur étapes idempotentes puis routage DLQ et alerte opérateur si compensation critique en échec.",
      "mermaidDiagram": "sequenceDiagram\\n  participant O as OrderSagaOrchestrator\\n  participant S as StockService\\n  participant P as PaymentService\\n  O->>S: reserveStock(orderId)\\n  S-->>O: StockReserved\\n  O->>P: authorizePayment(orderId)\\n  alt Paiement refusé\\n    P-->>O: PaymentFailed\\n    O->>S: releaseStock(orderId)\\n  end",
      "compensationMatrix": [
        {
          "id": "comp_existant (optionnel)",
          "step": "1. Réservation stock",
          "nominalAction": "reserveStock(orderId, items)",
          "compensationAction": "releaseStock(orderId, items)",
          "rollbackTrigger": "PaymentFailed ou Timeout étape 2",
          "criticality": "critical|high|medium|low",
          "idempotent": true,
          "retryable": true,
          "timeout": "5s"
        }
      ]
    }
  ],
  "removeSagas": ["id, code ou nom de la Saga à supprimer"]
}
''';

  /// Construit le prompt complet d'un tour IA en injectant le domaine en cours,
  /// ses contrats/couches Domain et l'ensemble des artefacts du projet actif.
  static String buildTurnPrompt({
    required FunctionalDomain domain,
    required DomainCatalog catalog,
    required UseCaseOrchestrationTab activeTab,
    required List<SpecChatMessage> history,
    required String userInput,
    required BusinessObjectModelPreferences modelPreferences,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    SpecForgeProject? activeProject,
    CompanyGlossary? companyGlossary,
    int maxHistoryEntries = 10,
  }) {
    final orchestration =
        domain.useCaseOrchestration ?? UseCaseOrchestrationSpec.empty;
    final contracts = domain.contracts ?? DomainContracts.empty;
    final domainServices = catalog.microservices
        .where((service) => service.domainId == domain.id)
        .toList();
    final otherDomains = catalog.domains
        .where((item) => item.id != domain.id)
        .toList();

    final buf = StringBuffer()
      ..writeln(
        'CONTEXTE : CAS D’USAGE & ORCHESTRATION (DDD / CQRS / SAGA) '
        'POUR LE DOMAINE « ${domain.name} » (${domain.domainCode})',
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
      ..writeln('DOMAINE EN COURS :')
      ..writeln('- id : ${domain.id}')
      ..writeln('- code : ${domain.domainCode}')
      ..writeln('- nom : ${domain.name}')
      ..writeln(
        '- description : ${domain.description.isEmpty ? '(aucune)' : domain.description}',
      )
      ..writeln(
        '- ONGLET ACTIF CONSULTÉ PAR L’UTILISATEUR : '
        '${activeTab.label} (${activeTab.subtitle})',
      );

    if (domainServices.isNotEmpty) {
      buf.writeln('- microservices du domaine :');
      for (final svc in domainServices) {
        buf.writeln(
          '  * ${svc.serviceCode} (${svc.name})'
          '${svc.description.isEmpty ? '' : ' — ${svc.description}'}',
        );
      }
    }

    if (otherDomains.isNotEmpty) {
      buf.writeln(
        '- autres domaines du workspace (pour identifier d’éventuelles Sagas inter-contextes) : '
        '${otherDomains.map((d) => '${d.name} (${d.domainCode})').join(', ')}',
      );
    }

    // Modèles, DTO, événements et couches Domain déjà modélisés dans le domaine.
    buf
      ..writeln()
      ..writeln('CONTRATS & COUCHES DOMAIN DU DOMAINE EN COURS :');
    final allEntries = contracts.groups.expand((g) => g.children).toList();
    if (allEntries.isEmpty) {
      buf.writeln('(aucun contrat défini dans Modèles & Contrats pour ce domaine)');
    } else {
      for (final entry in allEntries) {
        final obj = contracts.objectFor(entry);
        final layer = contracts.domainLayerFor(entry);
        final attrNames = [for (final a in obj.attributes) '${a.name}:${a.type.name}'];
        buf.writeln(
          '- [${entry.type}] ${obj.technicalName} (rubrique: ${entry.parent?.name ?? ''})'
          '${obj.description.isEmpty ? '' : ' — ${obj.description}'}',
        );
        if (attrNames.isNotEmpty) {
          buf.writeln('  attributs: ${attrNames.join(', ')}');
        }
        if (layer.isNotEmpty) {
          final cmdMethods = [
            for (final c in layer.stateChanges) ...c.associatedMethods,
          ];
          final qryMethods = [
            for (final q in layer.queries) ...q.associatedMethods,
          ];
          final evtMethods = [
            for (final e in layer.domainEvents) ...e.associatedMethods,
          ];
          final repoName = layer.persistencePolicy.repositoryPortName;
          final repoMethods = [
            for (final m in layer.persistencePolicy.portMethods)
              ...m.associatedMethods,
          ];
          if (cmdMethods.isNotEmpty) {
            buf.writeln('  Domain State changing: ${cmdMethods.join(', ')}');
          }
          if (qryMethods.isNotEmpty) {
            buf.writeln('  Domain Queries: ${qryMethods.join(', ')}');
          }
          if (evtMethods.isNotEmpty) {
            buf.writeln('  Domain Events: ${evtMethods.join(', ')}');
          }
          if (repoName.isNotEmpty || repoMethods.isNotEmpty) {
            buf.writeln(
              '  Repository Port ${repoName.isEmpty ? '(non nommé)' : repoName}: '
              '${repoMethods.join(', ')}',
            );
          }
        }
      }
    }

    // Artefacts du projet Spec actif ({{usecase}}, EXF, RG, Event Storming, Objets métiers).
    buf.writeln();
    if (activeProject == null) {
      buf.writeln(
        'PROJET SPEC EN COURS : (aucun projet Spec ouvert — appuie-toi sur les '
        'contrats du domaine ci-dessus, les pièces jointes ou pose des questions si nécessaire).',
      );
    } else {
      buf.writeln(
        'ARTEFACTS DU PROJET SPEC EN COURS « ${activeProject.name} » (${activeProject.id}) :',
      );
      if (activeProject.vision.ideaSummary.isNotEmpty) {
        buf.writeln('- Vision : ${activeProject.vision.ideaSummary}');
      }
      if (activeProject.vision.personas.isNotEmpty) {
        buf.writeln(
          '- Acteurs / Personas : '
          '${activeProject.vision.personas.map((a) => '${a.name}${a.role.isEmpty ? '' : ' (${a.role})'}').join(', ')}',
        );
      }

      final specUseCases = activeProject.cahierDesCharges.useCases;
      buf.writeln(
        '- CAS D’USAGE DU CAHIER DES CHARGES ({{usecase}}, ${specUseCases.length}) :',
      );
      if (specUseCases.isEmpty) {
        buf.writeln('  (aucun cas d’usage saisi dans le cahier des charges)');
      } else {
        for (final uc in specUseCases) {
          buf.writeln(
            '  * [${uc.id}] ${uc.title}'
            '${uc.actorId.isEmpty ? '' : ' (acteur: ${uc.actorId})'}',
          );
          if (uc.preconditions.isNotEmpty) {
            buf.writeln('    préconditions: ${uc.preconditions.join(' ; ')}');
          }
          if (uc.mainFlow.isNotEmpty) {
            buf.writeln('    flux principal: ${uc.mainFlow.join(' -> ')}');
          }
          if (uc.alternativeFlows.isNotEmpty) {
            buf.writeln(
              '    alternatives/erreurs: ${uc.alternativeFlows.join(' ; ')}',
            );
          }
          if (uc.postconditions.isNotEmpty) {
            buf.writeln('    postconditions: ${uc.postconditions.join(' ; ')}');
          }
        }
      }

      final reqs = activeProject.cahierDesCharges.functionalRequirements;
      if (reqs.isNotEmpty) {
        buf.writeln('- EXIGENCES FONCTIONNELLES (${reqs.length}) :');
        for (final r in reqs) {
          buf.writeln(
            '  * ${r.code} (${r.priority.code}) : ${r.title}'
            '${r.description.isEmpty ? '' : ' — ${r.description}'}',
          );
        }
      }

      final rules = activeProject.businessRules;
      if (rules.isNotEmpty) {
        buf.writeln('- RÈGLES DE GESTION (${rules.length}) :');
        for (final r in rules) {
          final detail = r.description.isNotEmpty
              ? r.description
              : [
                  if (r.trigger.isNotEmpty) 'Quand ${r.trigger}',
                  if (r.condition.isNotEmpty) 'Si ${r.condition}',
                  if (r.effect.isNotEmpty) 'Alors ${r.effect}',
                ].join(' · ');
          buf.writeln(
            '  * ${r.code} [${r.category.label}] ${r.title} : $detail',
          );
        }
      }

      final es = activeProject.eventStorming;
      if (es.hasContent) {
        buf.writeln(
          '- EVENT STORMING DSL v1.0 (${es.documents.length} Bounded Context(s), ${es.totalStepCount} étape(s)) :',
        );
        for (final doc in es.documents) {
          buf.writeln(
            '  * Contexte « ${doc.meta.boundedContext} » (${doc.fileName}, format: ${doc.meta.format.yamlValue}) :',
          );
          for (final step in doc.sortedSteps) {
            final target = step.aggregate.isNotEmpty
                ? step.aggregate
                : step.externalSystem;
            final eventsText = step.hasOutcomes
                ? step.outcomes
                      .map(
                        (o) =>
                            '${o.domainEvent.id}:${o.domainEvent.name}${o.isError ? ' [ERREUR]' : ''}',
                      )
                      .join(' | ')
                : '${step.domainEvent!.id}:${step.domainEvent!.name}';
            final trig = step.triggeredBy != null
                ? ' [triggered_by: ${step.triggeredBy!.summaryLabel}]'
                : '';
            buf.writeln(
              '    - Step ${step.step}$trig : ${step.command.name}'
              '${target.isEmpty ? '' : ' -> $target'} => $eventsText',
            );
          }
        }
      }

      if (activeProject.businessObjects.isNotEmpty) {
        buf.writeln(
          '- OBJETS MÉTIERS DU PROJET (${activeProject.businessObjects.length}) : '
          '${activeProject.businessObjects.map((o) => o.technicalName).join(', ')}',
        );
      }
    }

    final currentSnapshot = const JsonEncoder.withIndent('  ').convert({
      'cartography': [for (final c in orchestration.cartography) c.toJson()],
      'useCases': [for (final u in orchestration.useCases) u.toJson()],
      'sagas': [for (final s in orchestration.sagas) s.toJson()],
    });
    buf
      ..writeln()
      ..writeln('ÉTAT ACTUEL « CAS D’USAGE & ORCHESTRATION » DU DOMAINE (JSON) :')
      ..writeln(currentSnapshot);

    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');
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
  static ({UseCaseOrchestrationSpec spec, String summary}) applyPatch(
    UseCaseOrchestrationSpec current,
    Map<String, Object?> patch,
  ) {
    final summaryParts = <String>[];

    // 1. Cartographie par Bounded Context
    final cartography = List<BoundedContextUseCaseMap>.from(
      current.cartography,
    );
    final removeCartography = _readStringSet(patch['removeCartography']);
    var cartoRemoved = 0;
    if (removeCartography.isNotEmpty) {
      cartography.removeWhere((item) {
        final hit =
            removeCartography.contains(item.id.toLowerCase()) ||
            removeCartography.contains(item.boundedContext.toLowerCase());
        if (hit) cartoRemoved++;
        return hit;
      });
    }
    var cartoAdded = 0;
    var cartoUpdated = 0;
    final rawCartography = patch['cartography'];
    if (rawCartography is List) {
      for (final raw in rawCartography) {
        if (raw is! Map) continue;
        final rawId = (raw['id'] as String?)?.trim() ?? '';
        final rawCtx = (raw['boundedContext'] as String?)?.trim() ?? '';
        final existingIdx = cartography.indexWhere(
          (item) =>
              (rawId.isNotEmpty && item.id == rawId) ||
              (rawCtx.isNotEmpty &&
                  item.boundedContext.toLowerCase() == rawCtx.toLowerCase()),
        );
        final parsed = BoundedContextUseCaseMap.fromJson({
          ...raw,
          'id': existingIdx >= 0
              ? cartography[existingIdx].id
              : (rawId.isEmpty ? 'bcmap_${shortid.generate()}' : rawId),
        });
        if (existingIdx >= 0) {
          cartography[existingIdx] = parsed;
          cartoUpdated++;
        } else {
          cartography.add(parsed);
          cartoAdded++;
        }
      }
    }
    _appendCountSummary(
      summaryParts,
      label: 'contexte(s)',
      added: cartoAdded,
      updated: cartoUpdated,
      removed: cartoRemoved,
    );

    // 2. Use Cases applicatifs CQRS
    final useCases = List<ApplicationUseCaseSpec>.from(current.useCases);
    final removeUseCases = _readStringSet(patch['removeUseCases']);
    var ucRemoved = 0;
    if (removeUseCases.isNotEmpty) {
      useCases.removeWhere((uc) {
        final hit =
            removeUseCases.contains(uc.id.toLowerCase()) ||
            removeUseCases.contains(uc.code.toLowerCase()) ||
            removeUseCases.contains(uc.name.toLowerCase()) ||
            removeUseCases.contains(uc.title.toLowerCase());
        if (hit) ucRemoved++;
        return hit;
      });
    }
    var ucAdded = 0;
    var ucUpdated = 0;
    final rawUseCases = patch['useCases'];
    if (rawUseCases is List) {
      for (var i = 0; i < rawUseCases.length; i++) {
        final raw = rawUseCases[i];
        if (raw is! Map) continue;
        final rawId = (raw['id'] as String?)?.trim() ?? '';
        final rawCode = (raw['code'] as String?)?.trim() ?? '';
        final rawName = (raw['name'] as String?)?.trim() ?? '';
        final existingIdx = useCases.indexWhere(
          (uc) =>
              (rawId.isNotEmpty && uc.id == rawId) ||
              (rawCode.isNotEmpty &&
                  uc.code.toLowerCase() == rawCode.toLowerCase()) ||
              (rawName.isNotEmpty &&
                  uc.name.toLowerCase() == rawName.toLowerCase()),
        );
        final nextCode = rawCode.isNotEmpty
            ? rawCode
            : (existingIdx >= 0
                  ? useCases[existingIdx].code
                  : 'UC-${(useCases.length + 1).toString().padLeft(3, '0')}');
        final parsed = ApplicationUseCaseSpec.fromJson({
          ...raw,
          'id': existingIdx >= 0
              ? useCases[existingIdx].id
              : (rawId.isEmpty ? 'uc_${shortid.generate()}' : rawId),
          'code': nextCode,
        }, fallbackIndex: i);
        if (existingIdx >= 0) {
          useCases[existingIdx] = parsed.copyWith(
            states: raw.containsKey('states')
                ? parsed.states
                : useCases[existingIdx].states,
            version: raw.containsKey('version')
                ? parsed.version
                : useCases[existingIdx].version,
          );
          ucUpdated++;
        } else {
          useCases.add(parsed);
          ucAdded++;
        }
      }
    }
    _appendCountSummary(
      summaryParts,
      label: 'Use Case(s)',
      added: ucAdded,
      updated: ucUpdated,
      removed: ucRemoved,
    );

    // 3. Sagas & matrices de compensation
    final sagas = List<OrchestrationSagaSpec>.from(current.sagas);
    final removeSagas = _readStringSet(patch['removeSagas']);
    var sagaRemoved = 0;
    if (removeSagas.isNotEmpty) {
      sagas.removeWhere((saga) {
        final hit =
            removeSagas.contains(saga.id.toLowerCase()) ||
            removeSagas.contains(saga.code.toLowerCase()) ||
            removeSagas.contains(saga.name.toLowerCase()) ||
            removeSagas.contains(saga.title.toLowerCase());
        if (hit) sagaRemoved++;
        return hit;
      });
    }
    var sagaAdded = 0;
    var sagaUpdated = 0;
    final rawSagas = patch['sagas'];
    if (rawSagas is List) {
      for (var i = 0; i < rawSagas.length; i++) {
        final raw = rawSagas[i];
        if (raw is! Map) continue;
        final rawId = (raw['id'] as String?)?.trim() ?? '';
        final rawCode = (raw['code'] as String?)?.trim() ?? '';
        final rawName = (raw['name'] as String?)?.trim() ?? '';
        final existingIdx = sagas.indexWhere(
          (saga) =>
              (rawId.isNotEmpty && saga.id == rawId) ||
              (rawCode.isNotEmpty &&
                  saga.code.toLowerCase() == rawCode.toLowerCase()) ||
              (rawName.isNotEmpty &&
                  saga.name.toLowerCase() == rawName.toLowerCase()),
        );
        final nextCode = rawCode.isNotEmpty
            ? rawCode
            : (existingIdx >= 0
                  ? sagas[existingIdx].code
                  : 'SAGA-${(sagas.length + 1).toString().padLeft(3, '0')}');
        final parsed = OrchestrationSagaSpec.fromJson({
          ...raw,
          'id': existingIdx >= 0
              ? sagas[existingIdx].id
              : (rawId.isEmpty ? 'saga_${shortid.generate()}' : rawId),
          'code': nextCode,
        }, fallbackIndex: i);
        if (existingIdx >= 0) {
          sagas[existingIdx] = parsed.copyWith(
            states: raw.containsKey('states')
                ? parsed.states
                : sagas[existingIdx].states,
            version: raw.containsKey('version')
                ? parsed.version
                : sagas[existingIdx].version,
          );
          sagaUpdated++;
        } else {
          sagas.add(parsed);
          sagaAdded++;
        }
      }
    }
    _appendCountSummary(
      summaryParts,
      label: 'Saga(s)',
      added: sagaAdded,
      updated: sagaUpdated,
      removed: sagaRemoved,
    );

    final next = current.copyWith(
      cartography: cartography,
      useCases: useCases,
      sagas: sagas,
    );
    next.validate();
    return (spec: next, summary: summaryParts.join(', '));
  }

  static Set<String> _readStringSet(Object? raw) {
    if (raw is! List) return const <String>{};
    return {
      for (final item in raw)
        if (item != null && '$item'.trim().isNotEmpty)
          '$item'.trim().toLowerCase(),
    };
  }

  static void _appendCountSummary(
    List<String> parts, {
    required String label,
    required int added,
    required int updated,
    required int removed,
  }) {
    if (added == 0 && updated == 0 && removed == 0) return;
    final sub = <String>[
      if (added > 0) '+$added',
      if (updated > 0) '~$updated',
      if (removed > 0) '-$removed',
    ];
    parts.add('${sub.join('/')} $label');
  }
}
