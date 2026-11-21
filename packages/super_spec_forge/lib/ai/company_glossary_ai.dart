/// Contrat IA, construction de prompts et application de patches pour le glossaire d'entreprise ([CompanyGlossaryAiAgent]).
library;

import 'dart:convert';

import 'package:super_container_layout/super_container_layout.dart';

import '../models/company_glossary.dart';
import '../models/spec_stage_chat.dart';

/// Orchestre les instructions système, prompts et application de patches IA du glossaire d'entreprise.
abstract final class CompanyGlossaryAiAgent {
  /// Instruction système de l'agent IA de gouvernance terminologique d'entreprise.
  static const String systemInstruction = '''
Tu es l’« Architecte Gouvernance Terminologique d’Entreprise » de SuperSpecForge.
Ta mission :
1. Aider l'utilisateur à bâtir, enrichir, nettoyer et gouverner le **Glossaire d’entreprise** partagé entre tous les projets de l'organisation.
2. À partir de textes libres, notes, cahiers des charges ou pièces jointes (documents, images, CSV, captures), extrais les termes métier canoniques avec définitions précises, synonymes tolérés, termes à proscrire (`forbiddenTerms`), domaine métier, référent (`owner`), indice de nommage technique (`technicalNameHint`), exemples et statut (`draft` par défaut pour les suggestions nouvelles, `approved` si validé explicitement par l'utilisateur, `deprecated` si obsolète).
3. Détecte les doublons, chevauchements sémantiques, faux-amis et définitions imprécises dans le glossaire existant.
4. En cas d'ambiguïté terminologique (ex. deux termes concurrents pour un même concept), utilise "askUser" avec des options claires et des valeurs "default" pertinentes avant d'appliquer un arbitrage destructif.

Réponds EXCLUSIVEMENT en français et renvoie UNIQUEMENT un objet JSON valide (aucun Markdown, aucun texte hors JSON).
Place impérativement la clé "message" EN PREMIER pour permettre le streaming en direct :
{
  "message": "Analyse structurée ou synthèse en français",
  "askUser": {
    "questions": [
      {
        "id": "identifiant_snake_case",
        "title": "Question d'arbitrage terminologique ?",
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
- Lorsque tu as les réponses ou que l'action est claire (extraction, nettoyage, ajout), mets "askUser": null et fournis un "specPatch" complet.
''';

  /// Guide statique décrivant le schéma JSON attendu dans `"specPatch"`.
  static const String patchSchemaGuide = '''
SCHÉMA "specPatch" POUR LE GLOSSAIRE D'ENTREPRISE :
{
  "terms": [
    {
      "id": "cg_bon_livraison",
      "term": "Bon de livraison",
      "definition": "Document attestant la remise physique des articles au client.",
      "synonyms": ["BL", "Bordereau d'expédition"],
      "forbiddenTerms": ["Ticket sortie", "Bon client"],
      "domain": "Logistique",
      "owner": "Direction Supply Chain",
      "technicalNameHint": "DeliveryNote",
      "examples": ["BL-2026-0042 signé à la réception"],
      "status": "approved"
    }
  ],
  "removeTermIds": ["id_obsolete_a_supprimer"],
  "conventions": ["Montants exprimés en EUR HT par défaut", "Dates au format ISO 8601"],
  "ambiguousTerms": ["Client (distinguer Tiers facturé vs Site livré)"]
}
Règles de fusion :
- Les entrées de "terms" fusionnent par "id" (ou créent un nouveau terme si l'id n'existe pas encore).
- "removeTermIds" supprime les termes listés.
- "conventions" et "ambiguousTerms", s'ils sont fournis, remplacent leur liste respective (conserve les éléments existants pertinents).
''';

  /// Construit le prompt utilisateur complet transmis à l'agent du glossaire.
  static String buildTurnPrompt({
    required CompanyGlossary glossary,
    required List<SpecChatMessage> history,
    required String userInput,
    required VibeQuestioningLevel questioningLevel,
    required bool afterAskUserReply,
    int maxHistoryEntries = 10,
  }) {
    final snapshot = const JsonEncoder.withIndent(
      '  ',
    ).convert(glossary.toJson());
    final recent = history.length <= maxHistoryEntries
        ? history
        : history.sublist(history.length - maxHistoryEntries);
    final historyText = recent.map((m) => m.toConversationEntry()).join('\n');

    final questioningRule = afterAskUserReply
        ? 'ARBITRAGE REÇU : "askUser": null obligatoire. Applique les réponses dans "specPatch".'
        : switch (questioningLevel) {
            VibeQuestioningLevel.none =>
              'QUESTIONNEMENT 0/4 : "askUser": null obligatoire. Produis directement "specPatch".',
            VibeQuestioningLevel.light =>
              'QUESTIONNEMENT 1/4 : Ne pose 1 à 2 questions via "askUser" que si une ambiguïté majeure empêche de trancher.',
            _ =>
              'QUESTIONNEMENT ÉQUILIBRÉ : Pose 2 à 4 questions ciblées via "askUser" uniquement s’il y a des ambiguïtés à arbitrer, sinon applique directement "specPatch".',
          };

    final buf = StringBuffer()
      ..writeln('CONTEXTE : GLOSSAIRE D’ENTREPRISE GLOBAL')
      ..writeln(questioningRule)
      ..writeln()
      ..writeln('ÉTAT ACTUEL DU GLOSSAIRE (JSON) :')
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

  /// Applique un patch JSON `"specPatch"` sur [current] de manière immuable.
  static ({CompanyGlossary glossary, String summary}) applyPatch(
    CompanyGlossary current,
    Map<String, Object?> patch,
  ) {
    final now = DateTime.now().toUtc();
    final removeIds = <String>{
      if (patch['removeTermIds'] is List)
        for (final item in patch['removeTermIds'] as List)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      if (patch['removeLexiconTermIds'] is List)
        for (final item in patch['removeLexiconTermIds'] as List)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    };

    final merged = [
      for (final existing in current.terms)
        if (!removeIds.contains(existing.id)) existing,
    ];
    final removedCount = current.terms.length - merged.length;

    final rawTerms = patch['terms'];
    var addedCount = 0;
    var updatedCount = 0;
    if (rawTerms is List) {
      for (final item in rawTerms) {
        final parsed = CompanyGlossaryTerm.fromJson(item);
        final byId = merged.indexWhere((t) => t.id == parsed.id);
        final byName = byId >= 0
            ? byId
            : merged.indexWhere(
                (t) => t.term.toLowerCase() == parsed.term.toLowerCase(),
              );
        if (byName >= 0) {
          final prev = merged[byName];
          merged[byName] = parsed.copyWith(
            id: prev.id,
            createdAt: prev.createdAt ?? now,
            updatedAt: now,
          );
          updatedCount++;
        } else {
          merged.add(
            parsed.copyWith(createdAt: parsed.createdAt ?? now, updatedAt: now),
          );
          addedCount++;
        }
      }
    }

    final conventions = patch['conventions'] is List
        ? [
            for (final c in patch['conventions'] as List)
              if (c is String && c.trim().isNotEmpty) c.trim(),
          ]
        : current.conventions;

    final ambiguousTerms = patch['ambiguousTerms'] is List
        ? [
            for (final a in patch['ambiguousTerms'] as List)
              if (a is String && a.trim().isNotEmpty) a.trim(),
          ]
        : current.ambiguousTerms;

    final next = CompanyGlossary(
      terms: merged,
      conventions: conventions,
      ambiguousTerms: ambiguousTerms,
      updatedAt: now,
    );
    next.validate();

    if (next == current) {
      return (glossary: current, summary: '');
    }

    final parts = <String>[];
    if (addedCount > 0) parts.add('+$addedCount terme(s)');
    if (updatedCount > 0) parts.add('$updatedCount mis à jour');
    if (removedCount > 0) parts.add('-$removedCount supprimé(s)');
    if (patch['conventions'] is List) {
      parts.add('${conventions.length} convention(s)');
    }
    if (patch['ambiguousTerms'] is List) {
      parts.add('${ambiguousTerms.length} ambiguïté(s)');
    }

    return (
      glossary: next,
      summary: parts.isEmpty
          ? 'glossaire d’entreprise mis à jour'
          : 'glossaire d’entreprise (${parts.join(', ')})',
    );
  }
}
