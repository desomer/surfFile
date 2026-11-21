/// Contrat IA, prompts et application de patches pour le détail d'un modèle ou
/// contrat de domaine ([DomainModelAiAgent]).
library;

import 'dart:convert';

import 'package:shortid/shortid.dart';
import 'package:super_container_layout/super_container_layout.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../models/business_object_model_preferences.dart';
import '../models/business_object_spec.dart';
import '../models/company_glossary.dart';
import '../models/domain_contracts.dart';
import '../models/spec_coherence_issue.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import 'spec_app_tools.dart';
import 'spec_prompt_builder.dart';
import 'spec_stage_agent.dart';

/// Orchestre les instructions, prompts et patches IA d'un seul modèle de domaine.
abstract final class DomainModelAiAgent {
  /// Libellé de l'arbre de la fiche cité par le bloc de focus du prompt.
  static const String treeLabel = 'Attributs du modèle';

  /// Outils de la spec exposés au chat d'un modèle : ceux qui lisent, valident
  /// ou pilotent l'unique objet de la fiche (sans cahier des charges, règles
  /// de gestion ni création d'un autre objet).
  static const Set<String> toolNames = {
    'get_lexicon_and_synonyms',
    'inspect_business_object',
    'get_debug_entries',
    'run_coherence_audit',
    'validate_yaml_light_schema',
    'focus_stage_or_object',
    'filter_business_objects',
  };

  /// Guide statique complet : schéma du patch puis guide des [toolNames].
  static String get staticGuide =>
      '$patchSchemaGuide\n\n---\n\n${SpecForgeToolRegistry.toolsGuide(toolNames: toolNames)}';

  /// Garde les diagnostics de cohérence portant sur l'objet [objectId] (les
  /// autres objets du projet temporaire ne sont que des cibles de référence).
  static bool Function(SpecCoherenceIssue issue) coherenceIssueFilterFor(
    String objectId,
  ) =>
      (issue) =>
          issue.targetRef == objectId ||
          issue.targetRef.startsWith('$objectId.');

  /// Projet temporaire de la fiche de [entry] : son objet, puis un objet vide
  /// par autre entrée référençable du domaine. Il alimente l'arbre, les
  /// éditeurs d'attributs, le bloc de focus du prompt et les outils IA.
  static SpecForgeProject modelProject(
    DomainContracts contracts,
    JsonNode entry, {
    required String domainId,
    required BusinessObjectModelPreferences modelPreferences,
  }) {
    final stubs = [
      for (final MapEntry(key: id, value: technicalName)
          in contracts.referenceTargetsOf(entry).entries)
        BusinessObjectSpec(
          id: id,
          name: switch (contracts.details[id]?.title) {
            final title? when title.isNotEmpty => title,
            _ => contracts.entryById(id)?.name ?? technicalName,
          },
          technicalName: technicalName,
        ),
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return SpecForgeProject(
      id: 'domain_$domainId',
      name: domainId,
      initialIdea: '',
      createdAt: epoch,
      updatedAt: epoch,
      businessObjects: [contracts.objectFor(entry), ...stubs],
      businessObjectModelPreferences: modelPreferences,
    );
  }

  /// Instruction système de l'agent de modélisation d'un modèle ou contrat.
  static const String systemInstruction =
      '''
Tu es l’« Architecte Modèles & Contrats » de SuperSpecForge.
Tu travailles sur UN SEUL modèle ou contrat d'un domaine fonctionnel : son nom, sa rubrique et son type sont fixés par le DSL du domaine, tu n'édites que ses attributs et sa description.
Ta mission :
1. Concevoir, compléter et corriger les attributs typés du modèle à partir des demandes, notes ou pièces jointes de l'utilisateur.
2. Respecter la nature du type DSL de l'entrée :
   - model : entité métier persistée (identifiant, attributs métier, références) ;
   - part : fragment réutilisable inclus dans d'autres modèles ;
   - component : composant structuré réutilisable ;
   - createxdto : DTO de création (pas d'identifiant technique ni de champs calculés) ;
   - updatexdto : DTO de mise à jour (champs majoritairement optionnels) ;
   - xresponsedto : réponse d'API complète ;
   - xlistitemdto : ligne de liste (champs de synthèse uniquement) ;
   - xquerydto : critères de recherche, tri et pagination (tous optionnels) ;
   - eventxpayloaddto : contenu métier d'un événement ;
   - eventxenvelopedto : enveloppe d'événement (eventId, type, occurredAt, source, payload) ;
   - flatfile : fichier plat (colonnes scalaires uniquement, sans sous-objet ni tableau).
3. Relier les autres entrées du domaine par des attributs de type "reference" plutôt que de dupliquer leurs champs.
4. En cas d'ambiguïté structurante (cardinalité, obligatoire, énumération), utilise "askUser" avec des options claires et des valeurs "default" pertinentes.
5. RÈGLES IMPÉRATIVES DE DIMENSIONNEMENT ET DE MODÉLISATION DES ATTRIBUTS (communes avec l’étape Objets métier de la spec) :
${SpecStageAgent.attributeModelingRules}
   - Pour un modèle de domaine, l’objet séparé de la RÈGLE 3 est une autre entrée du domaine : référence-la si elle figure dans « ENTRÉES RÉFÉRENÇABLES », sinon propose dans "message" de l’ajouter au DSL. Les relations se modélisent uniquement par des attributs "reference" ; le nom technique du modèle est fixé par le DSL.
   - Les noms d’attributs sont uniques dans l’objet.
6. PILOTAGE DE LA FICHE & SCOPE SÉLECTIONNÉ (communs avec l’étape Objets métier de la spec) :
${SpecStageAgent.workshopPilotingRules}
     * Dans la fiche, l’arbre « $treeLabel » ne montre que le modèle édité : passe toujours `stage: "businessObjects"` et, si besoin, `objectId` = id du modèle édité ; les autres entrées du domaine ne sont pas sélectionnables.
7. OUTILS : tu peux appeler les outils déclarés (`get_lexicon_and_synonyms`, `inspect_business_object`, `get_debug_entries`, `run_coherence_audit`, `validate_yaml_light_schema`, `focus_stage_or_object`, `filter_business_objects`) via le Function Calling natif (à privilégier) ou via {"message":"inspection","toolCalls":[{"id":"...","name":"...","arguments":{...}}],"specPatch":null} avant de répondre.

Réponds EXCLUSIVEMENT en français et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON).
Place impérativement la clé "message" EN PREMIER pour permettre le streaming en direct :
{
  "message": "Synthèse en français des choix de modélisation",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question de modélisation ?",
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
- Si tu poses des questions via "askUser", mets "specPatch": null (ou ne modifie que les faits certains) et propose toujours des valeurs "default".
- Lorsque l'action est claire, mets "askUser": null et fournis un "specPatch".
''';

  /// Guide statique décrivant le schéma JSON attendu dans `"specPatch"`.
  static const String patchSchemaGuide =
      '''
SCHÉMA "specPatch" POUR LE DÉTAIL D'UN MODÈLE :
{
  "description": "Rôle du modèle (optionnel, remplace la description)",
  "attributes": [
    {
      "id": "attr_existant (à reprendre pour modifier un attribut, à omettre pour en créer un)",
      "name": "montantTotal",
      "type": "string|integer|number|boolean|date|datetime|uuid|email|url|enumeration|reference|object|json",
      "required": true,
      "nullable": false,
      "unique": false,
      "isArray": false,
      "estimatedMaxRows": 20,
      "defaultValue": null,
      "enumValues": ["BROUILLON", "VALIDE"],
      "referenceObjectId": "id ou nom technique d'une entrée du domaine (type reference uniquement)",
      "description": "Sens métier du champ",
      "constraints": "min >= 0",
      "schemaConstraints": { "maxLength": 6, "pattern": "^[A-Z]{2}-\\d{3}\$", "x-mask": "UU-###", "x-searchable": true, "x-database-index": true, "examples": ["AB-123"] },
      "children": [ { "name": "rue", "type": "string" } ]
    }
  ],
  "removeAttributes": ["id ou nom d'un attribut à supprimer"]
}
EXEMPLES D’ATTRIBUTS (communs avec l’étape Objets métier ; dans un domaine, "referenceObjectId" cible une entrée de « ENTRÉES RÉFÉRENÇABLES ») :
[
${SpecStageAgent.attributeExamplesJson}
]
Règles de fusion :
- Chaque élément de "attributes" remplace intégralement l'attribut racine de même "id" (sinon de même "name") : renvoie-le complet, sous-attributs "children" compris. Un attribut inconnu est ajouté à la fin.
- "removeAttributes" supprime les attributs racine listés ; les attributs non mentionnés restent inchangés.
- Un attribut "reference" doit cibler une entrée listée dans « ENTRÉES RÉFÉRENÇABLES » (ou le modèle lui-même).
- Un attribut "object" porte ses sous-attributs dans "children" ; "isArray": true avec "estimatedMaxRows" ≤ 200 pour une collection.
''';

  /// Construit le prompt d'un tour de chat sur l'entrée [entry] de [contracts].
  static String buildTurnPrompt({
    required String domainName,
    required DomainContracts contracts,
    required JsonNode entry,
    required List<SpecChatMessage> history,
    required String userInput,
    required BusinessObjectModelPreferences modelPreferences,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    bool forceFollowUpQuestions = false,
    String domainId = '',
    CompanyGlossary? companyGlossary,
    List<String> focusedAttributePath = const <String>[],
    String filter = '',
    int maxHistoryEntries = 10,
  }) {
    final details = contracts.details[entry.id] ?? ContractDetails.defaults;
    final object = contracts.objectFor(entry);
    final snapshot = const JsonEncoder.withIndent('  ').convert({
      'description': object.description,
      'attributes': [for (final a in object.attributes) a.toJson()],
    });
    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');
    final targets = contracts.referenceTargetsOf(entry);

    final buf = StringBuffer()
      ..writeln('CONTEXTE : DÉTAIL D’UN MODÈLE DU DOMAINE « $domainName »')
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
      ..writeln('MODÈLE ÉDITÉ :')
      ..writeln('- id : ${entry.id}')
      ..writeln('- nom technique : ${object.technicalName}')
      ..writeln('- rubrique : ${entry.parent?.name ?? ''}')
      ..writeln('- type DSL : ${entry.type}')
      ..writeln(
        '- titre : ${details.title.isEmpty ? '(aucun)' : details.title}',
      )
      ..writeln('- version : ${details.version}')
      ..writeln()
      ..writeln('ÉTAT ACTUEL DU DÉTAIL (JSON) :')
      ..writeln(snapshot)
      ..writeln()
      ..writeln('ENTRÉES RÉFÉRENÇABLES DU DOMAINE :');
    if (targets.isEmpty) {
      buf.writeln('(aucune autre entrée)');
    }
    for (final MapEntry(key: id, value: name) in targets.entries) {
      final other = contracts.entryById(id)!;
      final title = contracts.details[id]?.title ?? '';
      buf.writeln(
        '- id : $id · nom technique : $name · type : ${other.type}'
        ' · rubrique : ${other.parent?.name ?? ''}'
        '${title.isEmpty ? '' : ' · titre : $title'}',
      );
    }

    final focusBlock = SpecPromptBuilder.buildFocusScopeBlock(
      project: modelProject(
        contracts,
        entry,
        domainId: domainId,
        modelPreferences: modelPreferences,
      ),
      focusedObjectId: focusedAttributePath.isEmpty ? null : entry.id,
      focusedAttributePath: focusedAttributePath,
      businessObjectFilter: filter,
      treeLabel: treeLabel,
    );
    if (focusBlock.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(focusBlock);
    }

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

  /// Applique un `"specPatch"` sur [current] de manière immuable.
  ///
  /// [referenceTargets] associe l'ID de chaque entrée référençable à son nom
  /// technique : une référence inconnue lève une [FormatException], ce qui
  /// relance le tour IA avec l'erreur.
  static ({BusinessObjectSpec object, String summary}) applyPatch(
    BusinessObjectSpec current,
    Map<String, Object?> patch, {
    required Map<String, String> referenceTargets,
  }) {
    final targets = {...referenceTargets, current.id: current.technicalName};
    String resolveReference(String raw, String attributeName) {
      final key = raw.trim();
      if (targets.containsKey(key)) return key;
      for (final MapEntry(key: id, value: name) in targets.entries) {
        if (name.toLowerCase() == key.toLowerCase()) return id;
      }
      throw FormatException(
        'Référence inconnue « $key » sur l’attribut « $attributeName » : '
        'utilisez un id ou un nom technique des entrées référençables.',
      );
    }

    BusinessAttribute resolve(BusinessAttribute attribute) =>
        attribute.copyWith(
          referenceObjectId: attribute.type == BusinessAttributeType.reference
              ? resolveReference(attribute.referenceObjectId, attribute.name)
              : attribute.referenceObjectId,
          children: [for (final child in attribute.children) resolve(child)],
        );

    final removeKeys = <String>{
      if (patch['removeAttributes'] case final List raw)
        for (final item in raw)
          if (item is String && item.trim().isNotEmpty)
            item.trim().toLowerCase(),
    };
    final merged = [
      for (final attribute in current.attributes)
        if (!removeKeys.contains(attribute.id.toLowerCase()) &&
            !removeKeys.contains(attribute.name.toLowerCase()))
          attribute,
    ];
    final removedCount = current.attributes.length - merged.length;

    var addedCount = 0;
    var updatedCount = 0;
    if (patch['attributes'] case final List rawAttributes) {
      for (final item in rawAttributes) {
        final parsed = resolve(BusinessAttribute.fromJson(item));
        final hasId = item is Map && item['id'] is String;
        var index = hasId ? merged.indexWhere((a) => a.id == parsed.id) : -1;
        if (index < 0) {
          index = merged.indexWhere(
            (a) => a.name.toLowerCase() == parsed.name.toLowerCase(),
          );
        }
        if (index >= 0) {
          if (merged[index] != parsed.copyWith(id: merged[index].id)) {
            merged[index] = parsed.copyWith(id: merged[index].id);
            updatedCount++;
          }
        } else {
          final taken = merged.any((a) => a.id == parsed.id);
          merged.add(
            hasId && !taken
                ? parsed
                : parsed.copyWith(id: 'attr_${shortid.generate()}'),
          );
          addedCount++;
        }
      }
    }

    final description = patch['description'] is String
        ? (patch['description'] as String).trim()
        : current.description;
    final next = current.copyWith(attributes: merged, description: description);
    next.validate();
    if (next == current) {
      return (object: current, summary: '');
    }

    final parts = [
      if (addedCount > 0) '+$addedCount attribut(s)',
      if (updatedCount > 0) '$updatedCount mis à jour',
      if (removedCount > 0) '-$removedCount supprimé(s)',
      if (description != current.description) 'description',
    ];
    return (
      object: next,
      summary: parts.isEmpty
          ? '${current.technicalName} mis à jour'
          : '${current.technicalName} (${parts.join(', ')})',
    );
  }
}
