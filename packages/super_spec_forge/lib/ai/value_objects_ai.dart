/// Agent IA spécialisé pour la conception, l'enrichissement et l'audit du
/// Catalogue des Value Objects en Architecture Hexagonale ([ValueObjectsAiAgent]).
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/company_glossary.dart';
import '../models/domain_catalog.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import '../models/value_object_spec.dart';
import '../services/value_object_primitive_detector.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';

/// Résultat d'application d'un patch IA sur le catalogue de Value Objects.
class ValueObjectsPatchResult {
  /// Crée un résultat d'application de patch.
  const ValueObjectsPatchResult({
    required this.catalog,
    required this.summary,
    required this.addedCount,
    required this.updatedCount,
    required this.removedCount,
  });

  /// Catalogue de domaines mis à jour et validé.
  final DomainCatalog catalog;

  /// Résumé synthétique en français affiché dans la bulle de chat.
  final String summary;

  /// Nombre de Value Objects créés.
  final int addedCount;

  /// Nombre de Value Objects modifiés.
  final int updatedCount;

  /// Nombre de Value Objects supprimés.
  final int removedCount;

  /// Vrai si au moins une modification a été appliquée.
  bool get hasChanges =>
      addedCount > 0 || updatedCount > 0 || removedCount > 0;
}

/// Orchestre les instructions système, la construction du contexte et la fusion
/// déterministe des patches JSON pour le Catalogue des Value Objects
/// (Shared Kernel ou Domaine).
abstract final class ValueObjectsAiAgent {
  /// Outils d'inspection en lecture seule du projet Spec actif.
  static const Set<String> toolNames = <String>{
    'get_lexicon_and_synonyms',
    'get_requirements_summary',
    'inspect_business_object',
    'get_business_rules',
    'get_event_storming',
    'get_debug_entries',
  };

  /// Guide statique combinant le schéma `"specPatch"` et le guide des outils.
  static String get staticGuide =>
      '$patchSchemaGuide\n\n---\n\n${SpecForgeToolRegistry.toolsGuide(toolNames: toolNames)}';

  /// Instruction système de l'Architecte DDD spécialiste des Value Objects.
  static const String systemInstruction = r'''
Tu es l’« Architecte Value Objects (DDD / Architecture Hexagonale) » de SuperSpecForge.
Ta mission est de concevoir, normaliser et enrichir le **Catalogue des Value Objects** pour la portée active :
- **Shared Kernel (`shared`)** : Value Objects transverses réutilisables dans tous les domaines (`EmailAddress`, `Money`, `CurrencyCode`, `Iban`, `PhoneNumber`, `PostalAddress`, `DateRange`, `Percentage`, `Slug`…).
- **Domaine (`domain`)** : Value Objects propres à un Bounded Context précis (ex. `InvoiceNumber`, `SkuCode`, `TrackingCode`, `ShippingWeight`, `DiscountPolicy`…).

PRINCIPES FONDAMENTAUX D’UN VALUE OBJECT HEXAGONAL :
1. **Immuabilité & égalité structurelle** : un Value Object n’a pas d’identité propre (`id` technique) ; deux instances portant les mêmes valeurs sont égales.
2. **Auto-validation & lutte contre la Primitive Obsession** : remplace les primitifs porteurs de règles métier (formats, bornes, unités, devises, intervalles, normalisations) par des Value Objects explicites.
3. **Deux formes autorisées (`kind`)** :
   - `scalar` : encapsule UNE valeur primitive (`string`, `integer`, `number`, `boolean`, `date`, `datetime`, `uuid`, `email`, `url`, `enumeration`) avec ses `schemaConstraints` JSON Schema (minLength, maxLength, pattern, minimum, maximum, format, x-mask…), ses `normalizationRules` (ex. `trim`, `lowercase`, `uppercase`, `removeSpaces`) et ses `constraints`.
   - `composite` : regroupe plusieurs `fields` immuables cohérents (ex. `Money { amountMinorUnits, currency }`, `DateRange { startDate, endDate }`) avec des `crossFieldRules` (ex. `startDate <= endDate`). Un champ composite peut aussi être typé `valueObject` en référençant un autre VO existant (sans cycle).
4. **Exemples valides et contre-exemples invalides (`examples`)** : fournis systématiquement au moins 1 exemple valide (`isValid: true`) et 1 contre-exemple invalide (`isValid: false`) avec `reason` explicite pour alimenter la documentation et les tests TDD.
5. **Nommage technique strict** : `technicalName` en `PascalCase` ASCII uniquement (`^[A-Za-z_][A-Za-z0-9_-]*$`, sans accent ni espace). Évite de dupliquer dans un domaine un Value Object déjà présent dans le Shared Kernel sauf besoin de spécialisation métier explicite.

Réponds EXCLUSIVEMENT en français pour les explications (`message`, `askUser`, `name`, `description`, `reason`) et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON) en plaçant la clé `"message"` EN PREMIER :
{
  "message": "Synthèse claire en français des Value Objects créés ou enrichis",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question de modélisation DDD ?",
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
  static const String patchSchemaGuide = r'''
SCHÉMA "specPatch" POUR LE CATALOGUE DES VALUE OBJECTS :
{
  "upsertValueObjects": [
    {
      "id": "vo_existant (optionnel — conserver en cas de mise à jour)",
      "technicalName": "InvoiceNumber",
      "name": "Numéro de facture",
      "description": "Numéro séquentiel légal unique d'une facture client.",
      "category": "Identité|Contact|Finance|Temps|Localisation|Mesure|Métier",
      "version": "1.0.0",
      "kind": "scalar",
      "primitiveType": "string|integer|number|boolean|date|datetime|uuid|email|url|enumeration",
      "enumValues": [],
      "schemaConstraints": {
        "minLength": 11,
        "maxLength": 16,
        "pattern": "^FAC-\\d{4}-\\d{4,8}$"
      },
      "normalizationRules": ["trim", "uppercase"],
      "constraints": "Préfixe FAC- suivi de l'année et d'un compteur séquentiel.",
      "examples": [
        { "value": "FAC-2026-0001", "isValid": true, "reason": "Numéro nominal valide" },
        { "value": "2026-0001", "isValid": false, "reason": "Préfixe FAC- manquant" }
      ]
    },
    {
      "technicalName": "DateRange",
      "name": "Période calendaire",
      "description": "Intervalle immuable [startDate, endDate].",
      "category": "Temps",
      "version": "1.0.0",
      "kind": "composite",
      "fields": [
        { "name": "startDate", "type": "date", "required": true, "description": "Date de début" },
        { "name": "endDate", "type": "date", "required": true, "description": "Date de fin" }
      ],
      "crossFieldRules": ["startDate <= endDate"],
      "examples": [
        { "value": "{\"startDate\":\"2026-01-01\",\"endDate\":\"2026-01-31\"}", "isValid": true, "reason": "Période cohérente" },
        { "value": "{\"startDate\":\"2026-02-10\",\"endDate\":\"2026-02-01\"}", "isValid": false, "reason": "Fin antérieure au début" }
      ]
    }
  ],
  "removeValueObjects": ["id ou technicalName d'un Value Object à supprimer de cette portée"]
}
Règles de fusion :
- Chaque élément de "upsertValueObjects" remplace le Value Object existant de même "id" ou même "technicalName" dans la portée active, ou en ajoute un nouveau.
- Les Value Objects non mentionnés dans "upsertValueObjects" ni dans "removeValueObjects" sont conservés intacts.
- Pour un composite, un champ peut utiliser "type": "valueObject" et "valueObjectId": "TechnicalNameOuId" (sans cycle).
''';

  /// Construit le prompt d'un tour de chat sur le catalogue de Value Objects.
  static String buildTurnPrompt({
    required DomainCatalog catalog,
    required ValueObjectScope scope,
    FunctionalDomain? domain,
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
    final targetVos = scope == ValueObjectScope.shared
        ? catalog.sharedValueObjects
        : (domain?.valueObjects ?? const <ValueObjectSpec>[]);
    final snapshot = const JsonEncoder.withIndent('  ').convert([
      for (final vo in targetVos) vo.toJson(),
    ]);
    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');

    final scopeLabel = scope == ValueObjectScope.shared
        ? 'SHARED KERNEL (TRANSVERSE AU WORKSPACE)'
        : 'DOMAINE « ${domain?.name ?? ''} » (${domain?.domainCode ?? ''})';

    final buf = StringBuffer()
      ..writeln('CONTEXTE : CATALOGUE DES VALUE OBJECTS — $scopeLabel')
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

    if (scope == ValueObjectScope.domain && domain != null) {
      buf
        ..writeln()
        ..writeln('DOMAINE CIBLÉ :')
        ..writeln('- nom : ${domain.name} (${domain.domainCode})');
      if (domain.description.trim().isNotEmpty) {
        buf.writeln('- responsabilité : ${domain.description.trim()}');
      }
      if (catalog.sharedValueObjects.isNotEmpty) {
        buf.writeln('\nVALUE OBJECTS DÉJÀ PRÉSENTS DANS LE SHARED KERNEL (RÉUTILISABLES SANS DUPLICATION) :');
        for (final svo in catalog.sharedValueObjects) {
          buf.writeln(
            '- ${svo.technicalName} (${svo.name}, ${svo.kind.label}) : ${svo.formatStructureSummary()}',
          );
        }
      }
      final contracts = domain.contracts;
      if (contracts != null) {
        final modelLines = <String>[];
        for (final group in contracts.groups) {
          for (final node in group.children) {
            final obj = contracts.objectFor(node);
            if (obj.attributes.isEmpty) continue;
            final attrSummary = obj.attributes
                .take(12)
                .map(
                  (a) =>
                      '${a.name}:${a.type == BusinessAttributeType.valueObject ? 'VO(${a.valueObjectId})' : a.type.dslKeyword}${a.required ? '!' : ''}',
                )
                .join(', ');
            modelLines.add('- ${node.name} [${node.type}] : $attrSummary');
          }
        }
        if (modelLines.isNotEmpty) {
          buf
            ..writeln('\nMODÈLES & ATTRIBUTS ACTUELS DU DOMAINE :')
            ..writeln(modelLines.join('\n'));
        }
        final candidates = ValueObjectPrimitiveDetector.detectForDomain(
          catalog,
          domain.id,
        );
        if (candidates.isNotEmpty) {
          buf.writeln('\nCANDIDATS PRIMITIVE OBSESSION DÉTECTÉS AUTOMATIQUEMENT :');
          for (final c in candidates.take(12)) {
            buf.writeln(
              '- ${c.entryName}.${c.attribute.name} (${c.attribute.type.dslKeyword}) → suggéré : ${c.proposedSpec.technicalName} (${c.reason})',
            );
          }
        }
      }
    } else if (catalog.domains.isNotEmpty) {
      buf.writeln('\nDOMAINES DU WORKSPACE :');
      for (final d in catalog.domains) {
        buf.writeln(
          '- ${d.name} (${d.domainCode})${d.valueObjects.isNotEmpty ? ' · ${d.valueObjects.length} VO(s) locaux' : ''}',
        );
      }
    }

    if (activeProject != null) {
      buf
        ..writeln()
        ..writeln('PROJET SPEC ACTIF (POUR CONTEXTE MÉTIER) :')
        ..writeln('- ${activeProject.name} : ${activeProject.initialIdea}');
    }

    buf
      ..writeln()
      ..writeln('VALUE OBJECTS ACTUELS DANS LA PORTÉE ACTIVE (JSON) :')
      ..writeln(snapshot);

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

  /// Applique un `"specPatch"` sur le catalogue de Value Objects pour [scope]
  /// (et [domainId] si `scope == ValueObjectScope.domain`).
  static ValueObjectsPatchResult applyPatch(
    DomainCatalog catalog, {
    required ValueObjectScope scope,
    String? domainId,
    required Map<String, Object?> patch,
  }) {
    final FunctionalDomain? targetDomain = scope == ValueObjectScope.domain
        ? catalog.domains.where((d) => d.id == domainId).firstOrNull
        : null;
    if (scope == ValueObjectScope.domain && targetDomain == null) {
      throw FormatException('Domaine introuvable pour le patch VO : $domainId');
    }

    final currentList = scope == ValueObjectScope.shared
        ? catalog.sharedValueObjects
        : targetDomain!.valueObjects;

    final removeKeys = <String>{
      if (patch['removeValueObjects'] case final List raw)
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty)
            item.trim().toLowerCase(),
    };

    final merged = <ValueObjectSpec>[
      for (final vo in currentList)
        if (!removeKeys.contains(vo.id.toLowerCase()) &&
            !removeKeys.contains(vo.technicalName.toLowerCase()))
          vo,
    ];
    final removedCount = currentList.length - merged.length;

    var addedCount = 0;
    var updatedCount = 0;
    final rawUpserts = patch['upsertValueObjects'] ?? patch['valueObjects'];
    if (rawUpserts case final List list) {
      for (final rawItem in list) {
        final parsed = ValueObjectSpec.fromJson(rawItem);
        final hasId = rawItem is Map &&
            rawItem['id'] is String &&
            (rawItem['id'] as String).trim().isNotEmpty;
        var index = hasId ? merged.indexWhere((v) => v.id == parsed.id) : -1;
        if (index < 0) {
          index = merged.indexWhere(
            (v) =>
                v.technicalName.toLowerCase() ==
                parsed.technicalName.toLowerCase(),
          );
        }
        if (index >= 0) {
          final existing = merged[index];
          final candidate = parsed.copyWith(id: existing.id);
          if (existing != candidate) {
            merged[index] = candidate;
            updatedCount++;
          }
        } else {
          final idTaken = merged.any((v) => v.id == parsed.id) ||
              catalog.sharedValueObjects.any((v) => v.id == parsed.id);
          final nextId = (hasId && !idTaken)
              ? parsed.id
              : 'vo_${shortid.generate()}';
          merged.add(parsed.copyWith(id: nextId));
          addedCount++;
        }
      }
    }

    // Résout les références de champs de composites vers les IDs effectifs.
    final visiblePool = <ValueObjectSpec>[
      ...merged,
      if (scope == ValueObjectScope.domain) ...catalog.sharedValueObjects,
    ];
    final resolvedMerged = <ValueObjectSpec>[
      for (final vo in merged) _resolveCompositeFieldVoRefs(vo, visiblePool),
    ];

    final DomainCatalog nextCatalog;
    if (scope == ValueObjectScope.shared) {
      nextCatalog = catalog.copyWith(
        sharedValueObjects: resolvedMerged,
        updatedAt: DateTime.now().toUtc(),
      );
    } else {
      nextCatalog = catalog.copyWith(
        domains: [
          for (final d in catalog.domains)
            if (d.id == targetDomain!.id)
              d.copyWith(valueObjects: resolvedMerged)
            else
              d,
        ],
        updatedAt: DateTime.now().toUtc(),
      );
    }

    nextCatalog.validate();

    final parts = <String>[
      if (addedCount > 0) '+$addedCount Value Object(s)',
      if (updatedCount > 0) '$updatedCount mis à jour',
      if (removedCount > 0) '-$removedCount supprimé(s)',
    ];
    return ValueObjectsPatchResult(
      catalog: nextCatalog,
      summary: parts.join(', '),
      addedCount: addedCount,
      updatedCount: updatedCount,
      removedCount: removedCount,
    );
  }

  static ValueObjectSpec _resolveCompositeFieldVoRefs(
    ValueObjectSpec vo,
    List<ValueObjectSpec> pool,
  ) {
    if (!vo.isComposite) return vo;

    BusinessAttribute resolveAttr(BusinessAttribute attr) {
      var nextVoId = attr.valueObjectId;
      if (attr.type == BusinessAttributeType.valueObject &&
          nextVoId.trim().isNotEmpty) {
        final key = nextVoId.trim();
        final matched = pool
            .where(
              (v) =>
                  v.id == key ||
                  v.technicalName.toLowerCase() == key.toLowerCase(),
            )
            .firstOrNull;
        if (matched != null) {
          nextVoId = matched.id;
        }
      }
      return attr.copyWith(
        valueObjectId: nextVoId,
        children: [for (final c in attr.children) resolveAttr(c)],
      );
    }

    return vo.copyWith(fields: [for (final f in vo.fields) resolveAttr(f)]);
  }
}
