/// Agent IA spécialisé pour la gouvernance et l'urbanisme « Systèmes & Services »
/// par domaine ([SystemsServicesAiAgent]) : applications externes, fronts Web et
/// Mobile, BFF, (micro)services et applications monolithiques.
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/company_glossary.dart';
import '../models/domain_catalog.dart';
import '../models/domain_contracts.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';

/// Résultat d'application d'un patch IA sur les systèmes et services d'un domaine.
class SystemsServicesPatchResult {
  /// Crée un résultat d'application de patch.
  const SystemsServicesPatchResult({
    required this.catalog,
    required this.summary,
    required this.addedCount,
    required this.updatedCount,
    required this.removedCount,
  });

  /// Catalogue de domaines mis à jour et validé (incluant l'entrée d'audit).
  final DomainCatalog catalog;

  /// Résumé synthétique en français affiché dans la bulle de chat.
  final String summary;

  /// Nombre de systèmes/services créés.
  final int addedCount;

  /// Nombre de systèmes/services modifiés.
  final int updatedCount;

  /// Nombre de systèmes/services supprimés.
  final int removedCount;

  /// Indique si au moins une modification a été appliquée.
  bool get hasChanges =>
      addedCount > 0 || updatedCount > 0 || removedCount > 0;
}

/// Orchestre les instructions système, la construction du contexte projet/domaine
/// et la fusion déterministe des patches JSON pour « Systèmes & Services ».
abstract final class SystemsServicesAiAgent {
  /// Outils d'inspection en lecture seule du projet Spec actif.
  static const Set<String> toolNames = <String>{
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'get_event_storming',
    'inspect_business_object',
    'get_business_rules',
    'get_ux_overview',
    'get_debug_entries',
  };

  /// Guide statique combinant le schéma `"specPatch"` et le guide des outils.
  static String get staticGuide =>
      '$patchSchemaGuide\n\n---\n\n${SpecForgeToolRegistry.toolsGuide(toolNames: toolNames)}';

  /// Instruction système de l'Architecte Urbaniste SI (Domaines, Systèmes & Event Storming).
  static const String systemInstruction = r'''
Tu es un Architecte Urbaniste SI senior, expert en Domain-Driven Design (DDD), Architecture Hexagonale, BFF/Microservices et Event Storming.
Ta mission dans l’atelier « Systèmes & Services » est d’inventorier et de structurer, pour le domaine fonctionnel (Bounded Context) en cours, les composants applicatifs, les outils open-source et les dépendances externes selon 7 catégories strictes (`kind`) :
1. `externalApp` — **Application externe** : API tierce, SaaS externe, PSP (Stripe, Adyen…), passerelle email/SMS (SendGrid, Twilio…), ERP/CRM existant (SAP, Salesforce…), référentiel externe. **Rôle clé** : ces applications externes alimentent directement les post-its Rose pâle (`EXT-*`) de l’Event Storming !
2. `openSourceTool` — **Tools openSource** : brique ou outil open-source déployé / auto-hébergé sur lequel s’appuie le domaine (ex. Keycloak, Kafka, RabbitMQ, Meilisearch, Elasticsearch, MinIO, Camunda, n8n, Grafana, Matomo, Metabase…). **Rôle clé** : également importable comme système externe (`EXT-*`) en Event Storming lorsqu’il porte une responsabilité métier/technique identifiée (ex. IAM, moteur de workflow, recherche, stockage objet).
3. `webFront` — **Front Web** : application web (SPA, portail client, back-office métier, PWA) consommant les API/BFF du domaine.
4. `mobileApp` — **App Mobile** : application mobile native ou hybride (iOS / Android) exposant les parcours du domaine.
5. `bff` — **BFF (Backend For Frontend)** : façade applicative dédiée à l’agrégation et l’adaptation des contrats pour un canal Front Web ou Mobile.
6. `microservice` — **(Micro)Service** : service backend autonome portant la logique métier et la persistance d’un sous-ensemble cohérent du Bounded Context.
7. `monolith` — **Application monolithique** : application serveur unifiée ou monolithe modulaire portant l’ensemble du domaine.

RÈGLES D’URBANISME OBLIGATOIRES :
- **Codes canoniques (`serviceCode`)** : strictement en `kebab-case` minuscule (`^[a-z0-9]+(?:-[a-z0-9]+)*$`, 2 à 64 caractères), unique au sein du domaine (ex. `stripe-psp`, `keycloak-iam`, `customer-portal-web`, `mobile-shop-app`, `checkout-bff`, `order-service`, `core-erp-monolith`).
- **Préservation des identifiants** : lors d’une mise à jour d’un système existant, conserve son `id` ou son `serviceCode` exact pour éviter les doublons.
- **Fournisseur / Projet (`vendor`)** : renseigne systématiquement `vendor` pour les `externalApp` (ex. `"Stripe"`, `"SendGrid"`, `"SAP"`) et pour les `openSourceTool` (ex. `"Keycloak (Apache 2.0)"`, `"Apache Kafka"`, `"MinIO"`). Laisse vide `""` pour les composants développés en interne sauf progiciel spécifique.
- **Stack technique (`techStackId`)** : pour les composants internes (`webFront`, `mobileApp`, `bff`, `microservice`, `monolith`), associe uniquement un identifiant ou code présent dans les stacks techniques disponibles du workspace (ou `null` si aucune stack existante ne correspond — n’invente jamais un identifiant de stack inexistant). Pour `externalApp` et `openSourceTool`, laisse `techStackId` à `null`.
- **Aide à l’Event Storming** : identifie proactivement les systèmes tiers (`externalApp`) et les outils open-source (`openSourceTool`) évoqués dans la vision, le cahier des charges, les règles métier ou l’Event Storming du projet actif afin que le catalogue `EXT-*` soit complet et cohérent.
- **Choix d’architecture réaliste** : ne multiplie pas artificiellement les microservices si un monolithe modulaire (`monolith`) ou 1 à 2 services suffisent ; adapte le découpage (Fronts, BFF éventuel, Services/Monolithe, Tools openSource, Apps externes) à la taille et aux contraintes du domaine.

Réponds EXCLUSIVEMENT en français pour les explications métier (`message`, `askUser`, `name`, `description`) et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON) en plaçant la clé `"message"` EN PREMIER :
{
  "message": "Synthèse claire en français de la cartographie Systèmes & Services proposée",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question d’urbanisme ou de découpage applicatif ?",
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
- Lorsque l’action demandée est claire, mets `"askUser": null` et fournis un `"specPatch"`.
''';

  /// Guide statique décrivant le schéma JSON attendu dans `"specPatch"`.
  static const String patchSchemaGuide = '''
SCHÉMA "specPatch" POUR « SYSTÈMES & SERVICES » :
{
  "systems": [
    {
      "id": "service_existant (optionnel — conserver si modification)",
      "serviceCode": "stripe-psp",
      "name": "Passerelle de paiement Stripe",
      "kind": "externalApp|openSourceTool|webFront|mobileApp|bff|microservice|monolith",
      "vendor": "Stripe",
      "techStackId": null,
      "description": "Autorisation bancaire, capture des paiements et webhooks de statut.",
      "isActive": true
    },
    {
      "serviceCode": "order-portal-web",
      "name": "Portail Web Commandes",
      "kind": "webFront",
      "vendor": "",
      "techStackId": "id_ou_code_stack_existante_ou_null",
      "description": "Interface web permettant aux clients et gestionnaires de suivre les commandes.",
      "isActive": true
    }
  ],
  "removeSystems": ["id ou serviceCode du système/service à supprimer"]
}
Valeurs exactes autorisées pour `kind` :
- `externalApp` (Application externe — aide aux `EXT-*` de l’Event Storming)
- `openSourceTool` (Tools openSource — outils auto-hébergés/open-source tels que Keycloak, Kafka, MinIO, Meilisearch…)
- `webFront` (Front Web)
- `mobileApp` (App Mobile)
- `bff` (BFF - Backend For Frontend)
- `microservice` ((Micro)Service)
- `monolith` (Application monolithique)
''';

  /// Construit le prompt complet d'un tour IA pour le domaine [domain].
  static String buildTurnPrompt({
    required FunctionalDomain domain,
    required DomainCatalog catalog,
    required DomainSystemKind? activeFilterKind,
    required List<SpecChatMessage> history,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    SpecForgeProject? activeProject,
    CompanyGlossary? companyGlossary,
    int maxHistoryEntries = 10,
  }) {
    final domainSystems = catalog.microservices
        .where((item) => item.domainId == domain.id)
        .toList();
    final otherDomains = catalog.domains
        .where((item) => item.id != domain.id)
        .toList();
    final contracts = domain.contracts ?? DomainContracts.empty;

    final buf = StringBuffer()
      ..writeln(
        'CONTEXTE : ATELIER « SYSTÈMES & SERVICES » (URBANISME SI & AIDE EVENT STORMING) '
        'POUR LE DOMAINE « ${domain.name} » (${domain.domainCode})',
      )
      ..writeln(
        SpecPromptBuilder.questioningDirective(
          level: questioningLevel,
          afterAskUserReply: afterAskUserReply,
          forceFollowUpQuestions: forceFollowUpQuestions,
        ),
      );

    final glossaryBlock = SpecPromptBuilder.companyGlossaryBlock(
      companyGlossary,
    );
    if (glossaryBlock.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(glossaryBlock);
    }

    final domainDefaultStack = catalog.techStackForDomain(domain);
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
        '- stack par défaut du domaine : '
        '${domainDefaultStack == null ? '(aucune)' : '${domainDefaultStack.name} (id: ${domainDefaultStack.id}, code: ${domainDefaultStack.code})'}',
      )
      ..writeln(
        '- filtre actif dans l’interface : '
        '${activeFilterKind == null ? 'Toutes les catégories' : activeFilterKind.label}',
      );

    buf
      ..writeln()
      ..writeln('STACKS TECHNIQUES DISPONIBLES DANS LE WORKSPACE :');
    if (catalog.techStacks.isEmpty) {
      buf.writeln('(aucune stack technique configurée — utilise techStackId: null)');
    } else {
      for (final stack in catalog.techStacks) {
        buf.writeln(
          '- id: "${stack.id}" | code: "${stack.code}" | nom: "${stack.name}"'
          '${stack.description.isEmpty ? '' : ' — ${stack.description}'}',
        );
      }
    }

    if (otherDomains.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('AUTRES DOMAINES DU WORKSPACE (CONTEXTE INTER-DOMAINES) :');
      for (final other in otherDomains) {
        final otherServices = catalog.microservices
            .where((s) => s.domainId == other.id)
            .map((s) => '${s.serviceCode} [${s.kind.shortLabel}]')
            .toList();
        buf.writeln(
          '- ${other.name} (${other.domainCode})'
          '${otherServices.isEmpty ? '' : ' : ${otherServices.join(', ')}'}',
        );
      }
    }

    final allEntries = contracts.groups.expand((g) => g.children).toList();
    if (allEntries.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('MODÈLES & CONTRATS DÉJÀ DÉFINIS DANS CE DOMAINE :');
      for (final entry in allEntries) {
        final obj = contracts.objectFor(entry);
        buf.writeln(
          '- [${entry.type}] ${obj.technicalName}'
          '${obj.description.isEmpty ? '' : ' — ${obj.description}'}',
        );
      }
    }

    buf.writeln();
    if (activeProject == null) {
      buf.writeln(
        'PROJET SPEC ACTIF : (aucun projet Spec ouvert — appuie-toi sur la description du domaine, ses contrats et les échanges avec l’utilisateur).',
      );
    } else {
      buf.writeln(
        'ARTEFACTS DU PROJET SPEC ACTIF « ${activeProject.name} » (${activeProject.id}) :',
      );
      if (activeProject.vision.ideaSummary.isNotEmpty) {
        buf.writeln('- Vision : ${activeProject.vision.ideaSummary}');
      }
      if (activeProject.vision.personas.isNotEmpty) {
        buf.writeln(
          '- Acteurs / Personas : '
          '${activeProject.vision.personas.map((p) => '${p.name}${p.role.isEmpty ? '' : ' (${p.role})'}').join(', ')}',
        );
      }
      if (activeProject.cahierDesCharges.modules.isNotEmpty) {
        buf.writeln(
          '- Modules du cahier des charges : '
          '${activeProject.cahierDesCharges.modules.map((m) => m.name).join(', ')}',
        );
      }
      if (activeProject.uxSpec.screens.isNotEmpty) {
        buf.writeln(
          '- Écrans UX identifiés (${activeProject.uxSpec.screens.length}) : '
          '${activeProject.uxSpec.screens.take(15).map((s) => s.name).join(', ')}',
        );
      }
      if (activeProject.eventStorming.hasContent) {
        buf.writeln('- Event Storming existant :');
        for (final doc in activeProject.eventStorming.documents) {
          final exts = doc.catalog.externalSystems
              .map((e) => '${e.id}:${e.name}')
              .join(', ');
          buf.writeln(
            '  * Contexte « ${doc.meta.boundedContext} » (domaine: ${doc.meta.domain})'
            '${exts.isEmpty ? ' — aucun EXT-* déclaré' : ' — EXT-* actuels : $exts'}',
          );
        }
      }
    }

    final currentSnapshot = const JsonEncoder.withIndent('  ').convert({
      'systems': [for (final s in domainSystems) s.toJson()],
    });
    buf
      ..writeln()
      ..writeln('ÉTAT ACTUEL DES SYSTÈMES & SERVICES DU DOMAINE (JSON) :')
      ..writeln(currentSnapshot);

    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');
    if (historyText.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('HISTORIQUE RÉCENT DE LA CONVERSATION :')
        ..writeln(historyText);
    }

    buf
      ..writeln()
      ..writeln('DEMANDE UTILISATEUR POUR CE TOUR :')
      ..writeln(userInput.trim());

    return buf.toString();
  }

  /// Applique un `specPatch` sur les systèmes et services du domaine [domainId].
  static SystemsServicesPatchResult applyPatch(
    DomainCatalog catalog, {
    required String domainId,
    required Map<String, Object?> patch,
    String actorUsername = 'ai-assistant',
    DateTime? now,
  }) {
    final domain = catalog.domains.where((d) => d.id == domainId).firstOrNull;
    if (domain == null) {
      throw FormatException('Domaine introuvable : $domainId');
    }

    final otherDomainServices = catalog.microservices
        .where((s) => s.domainId != domainId)
        .toList();
    final working = catalog.microservices
        .where((s) => s.domainId == domainId)
        .toList();

    var added = 0;
    var updated = 0;
    var removed = 0;

    final rawRemoves = patch['removeSystems'] ?? patch['removeMicroservices'];
    if (rawRemoves is List) {
      for (final rawKey in rawRemoves) {
        final key = (rawKey?.toString() ?? '').trim();
        if (key.isEmpty) continue;
        final keyLower = key.toLowerCase();
        final idx = working.indexWhere(
          (s) =>
              s.id == key ||
              s.serviceCode.toLowerCase() == keyLower ||
              s.name.toLowerCase() == keyLower,
        );
        if (idx < 0) continue;
        final target = working[idx];
        final boundConfigs = catalog.configurationEntries
            .where((c) => c.microserviceId == target.id)
            .length;
        if (boundConfigs > 0) {
          throw FormatException(
            'Suppression refusée pour « ${target.name} » (${target.serviceCode}) : '
            '$boundConfigs entrée(s) de configuration y sont rattachées.',
          );
        }
        working.removeAt(idx);
        removed++;
      }
    }

    final rawSystems =
        patch['systems'] ?? patch['upsertSystems'] ?? patch['microservices'];
    if (rawSystems is List) {
      for (final rawItem in rawSystems) {
        if (rawItem is! Map) continue;
        final map = Map<String, Object?>.from(rawItem);
        final rawId = (map['id']?.toString() ?? '').trim();
        final rawName = (map['name']?.toString() ?? '').trim();
        final rawCode = (map['serviceCode'] ?? map['code'])?.toString().trim() ?? '';

        final existingIndex = working.indexWhere((s) {
          if (rawId.isNotEmpty && s.id == rawId) return true;
          if (rawCode.isNotEmpty &&
              s.serviceCode.toLowerCase() == rawCode.toLowerCase()) {
            return true;
          }
          if (rawCode.isEmpty &&
              rawName.isNotEmpty &&
              s.name.toLowerCase() == rawName.toLowerCase()) {
            return true;
          }
          return false;
        });
        final existing = existingIndex >= 0 ? working[existingIndex] : null;

        final effectiveName = rawName.isNotEmpty
            ? rawName
            : (existing?.name ?? _humanizeCode(rawCode));
        if (effectiveName.trim().length < 2) {
          throw const FormatException(
            'Chaque système ou service doit posséder un nom d’au moins 2 caractères.',
          );
        }

        final normalizedCode = rawCode.isNotEmpty
            ? normalizeKebabCode(rawCode)
            : (existing?.serviceCode ??
                  _nextUniqueCode(
                    normalizeKebabCode(effectiveName),
                    working,
                  ));

        final kind = map.containsKey('kind') || map.containsKey('type')
            ? DomainSystemKind.fromJson(map['kind'] ?? map['type'])
            : (existing?.kind ?? DomainSystemKind.microservice);

        final description = map.containsKey('description')
            ? (map['description']?.toString() ?? '').trim()
            : (existing?.description ?? '');

        final vendor = map.containsKey('vendor') || map.containsKey('provider')
            ? ((map['vendor'] ?? map['provider'])?.toString() ?? '').trim()
            : (existing?.vendor ?? '');

        final isActive = map['isActive'] is bool
            ? map['isActive'] as bool
            : (existing?.isActive ?? true);

        String? resolvedStackId = existing?.techStackId;
        if (map.containsKey('techStackId') || map.containsKey('techStack')) {
          final rawStack =
              ((map['techStackId'] ?? map['techStack'])?.toString() ?? '')
                  .trim();
          if (rawStack.isEmpty || rawStack.toLowerCase() == 'null') {
            resolvedStackId = null;
          } else {
            final stackMatch = catalog.techStacks.where((st) {
              final lower = rawStack.toLowerCase();
              return st.id == rawStack ||
                  st.code.toLowerCase() == lower ||
                  st.name.toLowerCase() == lower;
            }).firstOrNull;
            if (stackMatch != null) {
              resolvedStackId = stackMatch.id;
            } else if (kind.isOffTheShelf) {
              resolvedStackId = null;
            } else {
              throw FormatException(
                'Stack technique inconnue « $rawStack » pour $effectiveName. '
                'Stacks valides : ${catalog.techStacks.map((s) => s.code).join(', ')}.',
              );
            }
          }
        }
        if (kind.isOffTheShelf) {
          resolvedStackId = null;
        }

        final candidate = Microservice(
          id: existing?.id ?? 'service_${shortid.generate()}',
          domainId: domainId,
          serviceCode: normalizedCode,
          name: effectiveName,
          kind: kind,
          description: description,
          isActive: isActive,
          techStackId: resolvedStackId,
          vendor: vendor,
        );
        candidate.validate();

        // Évite toute collision de serviceCode avec un autre item du même domaine.
        final duplicateIdx = working.indexWhere(
          (s) => s.serviceCode == candidate.serviceCode && s.id != candidate.id,
        );
        if (duplicateIdx >= 0) {
          // Fusionne sur l'entrée existante portant déjà ce serviceCode.
          final prev = working[duplicateIdx];
          final merged = candidate.copyWith(id: prev.id);
          if (merged != prev) {
            working[duplicateIdx] = merged;
            updated++;
          }
          continue;
        }

        if (existing != null) {
          if (candidate != existing) {
            working[existingIndex] = candidate;
            updated++;
          }
        } else {
          working.add(candidate);
          added++;
        }
      }
    }

    if (added == 0 && updated == 0 && removed == 0) {
      return SystemsServicesPatchResult(
        catalog: catalog,
        summary: '',
        addedCount: 0,
        updatedCount: 0,
        removedCount: 0,
      );
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    final parts = <String>[
      if (added > 0) '+$added ajouté(s)',
      if (updated > 0) '$updated mis à jour',
      if (removed > 0) '-$removed supprimé(s)',
    ];
    final summary = '${domain.name} (${parts.join(', ')})';
    final auditAction = added > 0 && updated == 0 && removed == 0
        ? DomainAuditAction.create
        : (removed > 0 && added == 0 && updated == 0
              ? DomainAuditAction.delete
              : DomainAuditAction.update);
    final auditEntry = AuditLogEntry(
      id: 'audit_${shortid.generate()}',
      recordedAt: timestamp,
      actorUsername: actorUsername,
      domainId: domainId,
      actionType: auditAction,
      details: 'Systèmes & Services IA : ${parts.join(', ')}.',
    );

    final nextCatalog = catalog.copyWith(
      microservices: <Microservice>[...otherDomainServices, ...working],
      auditLog: <AuditLogEntry>[...catalog.auditLog, auditEntry],
      updatedAt: timestamp,
    );
    nextCatalog.validate();

    return SystemsServicesPatchResult(
      catalog: nextCatalog,
      summary: summary,
      addedCount: added,
      updatedCount: updated,
      removedCount: removed,
    );
  }

  /// Normalise une chaîne libre en `kebab-case` conforme aux contraintes `DomainCatalog`.
  static String normalizeKebabCode(String raw) {
    const accents = <String, String>{
      'à': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i',
      'ô': 'o', 'ö': 'o',
      'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'œ': 'oe', 'æ': 'ae',
    };
    final buf = StringBuffer();
    for (final rune in raw.trim().toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buf.write(accents[ch] ?? ch);
    }
    var slug = buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.length < 2) slug = 'sys-${slug.isEmpty ? 'item' : slug}';
    if (slug.length > 64) {
      slug = slug.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
    }
    return slug;
  }

  static String _nextUniqueCode(String base, List<Microservice> existing) {
    final taken = existing.map((e) => e.serviceCode).toSet();
    if (!taken.contains(base)) return base;
    for (var i = 2; i < 1000; i++) {
      final suffix = '-$i';
      final prefix = base.length + suffix.length > 64
          ? base.substring(0, 64 - suffix.length).replaceAll(RegExp(r'-+$'), '')
          : base;
      final candidate = '$prefix$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
    return base;
  }

  static String _humanizeCode(String code) {
    if (code.trim().isEmpty) return 'Système';
    final words = code
        .trim()
        .split(RegExp(r'[-_\s]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return code;
    return words
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
