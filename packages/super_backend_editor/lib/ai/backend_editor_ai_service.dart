/// Service d'assistance IA orienté domaine pour `super_backend_editor`
/// ([BackendEditorAiService], [GeminiBackendEditorAiService],
/// [BackendAiResponseParser], [BackendAiTurnResponse], [BackendAiSuggestion],
/// [BackendAiTaskKind]).
///
/// Exploite `streamGemini` et `warmUpGemini` de `super_container_layout` en
/// injectant le contexte complet du [BackendDomainProject] (modèles, Value
/// Objects, 7 onglets de la couche Domain hexagonale, Use Cases CQRS et
/// scénarios Given/When/Then, Sagas, collections/endpoints de l'overlay et
/// contrat exact de l'objet `ctx` du moteur QuickJS), sans jamais divulguer les
/// valeurs secrètes locales.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/backend_domain_project.dart';
import '../models/domain_design_spec.dart';
import '../models/json_value_utils.dart';

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

/// Catégorie de tâche demandée à l'assistant IA Backend.
enum BackendAiTaskKind {
  /// Assistance générale sur le domaine, l'architecture hexagonale et les APIs.
  generalAssistant(
    'Assistant général',
    'Répond aux questions métier/techniques et propose des artefacts actionnables.',
  ),

  /// Génération d'un handler ou validateur d'invariant JavaScript QuickJS.
  generateQuickJsHandler(
    'Générer un script QuickJS',
    'Écrit un script QuickJS conforme aux invariants DDD, Use Cases CQRS et API `ctx`.',
  ),

  /// Génération de jeux d'entités réalistes conformes aux JSON Schemas des collections.
  generateSeedEntities(
    'Générer des entités de seed',
    'Produit un jeu de données réaliste et cohérent pour peupler une collection.',
  ),

  /// Diagnostic d'écarts de cohérence Design ↔ Backend ou d'erreurs d'exécution.
  diagnoseCoherenceOrError(
    'Diagnostiquer cohérence / erreur',
    'Analyse une erreur runtime ou un écart Design/Backend et propose un correctif.',
  );

  const BackendAiTaskKind(this.label, this.description);

  /// Libellé court affiché dans l'interface.
  final String label;

  /// Description synthétique de l'objectif de la tâche.
  final String description;

  /// Désérialise une catégorie de tâche depuis JSON.
  static BackendAiTaskKind fromJson(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      for (final item in BackendAiTaskKind.values) {
        if (item.name == trimmed) return item;
      }
    }
    return BackendAiTaskKind.generalAssistant;
  }
}

/// Artefact structuré et actionnable proposé par l'assistant IA Backend.
@immutable
class BackendAiSuggestion {
  /// Crée une suggestion IA immuable.
  BackendAiSuggestion({
    required this.kind,
    required this.targetId,
    required this.title,
    this.codeOrJson = '',
    List<Map<String, Object?>> entities = const <Map<String, Object?>>[],
  }) : entities = freezeJsonMapList(entities);

  /// Valeurs canoniques autorisées pour [kind].
  static const Set<String> allowedKinds = <String>{
    'quickjs_script',
    'seed_entities',
    'endpoint_payload',
  };

  /// Nature de la suggestion (`'quickjs_script'`, `'seed_entities'` ou `'endpoint_payload'`).
  final String kind;

  /// Identifiant de la cible (chemin relatif du script, nom de collection ou ID d'endpoint).
  final String targetId;

  /// Titre court décrivant la suggestion dans l'interface.
  final String title;

  /// Code source JavaScript QuickJS ou représentation JSON formatée.
  final String codeOrJson;

  /// Liste d'entités JSON lorsque [kind] vaut `'seed_entities'`.
  final List<Map<String, Object?>> entities;

  /// Indique s'il s'agit d'un script JavaScript QuickJS (`'quickjs_script'`).
  bool get isQuickJsScript => kind == 'quickjs_script';

  /// Indique s'il s'agit d'un lot d'entités de seed (`'seed_entities'`).
  bool get isSeedEntities => kind == 'seed_entities';

  /// Indique s'il s'agit d'un payload de requête d'endpoint (`'endpoint_payload'`).
  bool get isEndpointPayload => kind == 'endpoint_payload';

  /// Vérifie les invariants de la suggestion.
  void validate() {
    if (!allowedKinds.contains(kind)) {
      throw FormatException(
        'BackendAiSuggestion.kind invalide : « $kind » '
        '(attendu : ${allowedKinds.join(', ')}).',
      );
    }
    if (targetId.trim().isEmpty) {
      throw const FormatException('BackendAiSuggestion.targetId requis.');
    }
    if (title.trim().isEmpty) {
      throw const FormatException('BackendAiSuggestion.title requis.');
    }
  }

  /// Retourne une copie modifiée.
  BackendAiSuggestion copyWith({
    String? kind,
    String? targetId,
    String? title,
    String? codeOrJson,
    List<Map<String, Object?>>? entities,
  }) => BackendAiSuggestion(
    kind: kind ?? this.kind,
    targetId: targetId ?? this.targetId,
    title: title ?? this.title,
    codeOrJson: codeOrJson ?? this.codeOrJson,
    entities: entities ?? this.entities,
  );

  /// Sérialise la suggestion en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'targetId': targetId,
    'title': title,
    'codeOrJson': codeOrJson,
    'entities': entities,
  };

  /// Désérialise de manière tolérante une suggestion depuis un objet JSON.
  factory BackendAiSuggestion.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException(
        'BackendAiSuggestion doit être un objet JSON.',
      );
    }
    final normalizedKind = _normalizeSuggestionKind(raw['kind']);
    final rawTarget =
        (raw['targetId'] ??
                raw['target'] ??
                raw['scriptPath'] ??
                raw['collection'] ??
                raw['endpointId'])
            ?.toString()
            .trim() ??
        '';
    final effectiveTarget = rawTarget.isNotEmpty ? rawTarget : normalizedKind;
    final rawTitle = (raw['title'] ?? raw['label'])?.toString().trim() ?? '';
    final effectiveTitle = rawTitle.isNotEmpty ? rawTitle : effectiveTarget;

    final rawCodeOrJsonValue =
        raw['codeOrJson'] ?? raw['code'] ?? raw['payload'] ?? raw['json'];
    var resolvedCodeOrJson = switch (rawCodeOrJsonValue) {
      String s => s,
      Map m => _prettyJson.convert(freezeJsonMap(m)),
      List l => _prettyJson.convert(freezeJsonValue(l)),
      _ => '',
    };

    var resolvedEntities = freezeJsonMapList(raw['entities']);
    if (normalizedKind == 'seed_entities') {
      if (resolvedEntities.isEmpty && resolvedCodeOrJson.trim().isNotEmpty) {
        resolvedEntities = _tryDecodeEntityList(resolvedCodeOrJson);
      }
      if (resolvedCodeOrJson.trim().isEmpty && resolvedEntities.isNotEmpty) {
        resolvedCodeOrJson = _prettyJson.convert(resolvedEntities);
      }
    }

    final item = BackendAiSuggestion(
      kind: normalizedKind,
      targetId: effectiveTarget,
      title: effectiveTitle,
      codeOrJson: resolvedCodeOrJson,
      entities: resolvedEntities,
    );
    item.validate();
    return item;
  }

  static String _normalizeSuggestionKind(Object? raw) {
    final text = (raw?.toString() ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[\s-]+'),
      '_',
    );
    switch (text) {
      case 'quickjs_script':
      case 'quickjs':
      case 'script':
      case 'js_script':
      case 'handler':
        return 'quickjs_script';
      case 'seed_entities':
      case 'seed':
      case 'entities':
      case 'seed_data':
        return 'seed_entities';
      case 'endpoint_payload':
      case 'payload':
      case 'request_payload':
      case 'body':
        return 'endpoint_payload';
      default:
        throw FormatException('Type de suggestion IA inconnu : $raw');
    }
  }

  static List<Map<String, Object?>> _tryDecodeEntityList(String rawText) {
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is List) {
        return freezeJsonMapList(decoded);
      }
      if (decoded is Map && decoded['items'] is List) {
        return freezeJsonMapList(decoded['items']);
      }
    } on FormatException {
      // Ignore un texte non-JSON.
    }
    return const <Map<String, Object?>>[];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendAiSuggestion &&
          other.kind == kind &&
          other.targetId == targetId &&
          other.title == title &&
          other.codeOrJson == codeOrJson &&
          deepJsonEquals(other.entities, entities);

  @override
  int get hashCode =>
      Object.hash(kind, targetId, title, codeOrJson, deepJsonHash(entities));
}

/// Réponse structurée d'un tour d'assistance IA Backend après analyse.
@immutable
class BackendAiTurnResponse {
  /// Crée une réponse de tour d'assistant IA.
  BackendAiTurnResponse({
    required this.replyMarkdown,
    List<BackendAiSuggestion> suggestions = const <BackendAiSuggestion>[],
  }) : suggestions = List<BackendAiSuggestion>.unmodifiable(suggestions);

  /// Réponse explicative formatée en Markdown français.
  final String replyMarkdown;

  /// Liste ordonnée des suggestions actionnables extraites de la réponse.
  final List<BackendAiSuggestion> suggestions;

  /// Retourne une copie modifiée.
  BackendAiTurnResponse copyWith({
    String? replyMarkdown,
    List<BackendAiSuggestion>? suggestions,
  }) => BackendAiTurnResponse(
    replyMarkdown: replyMarkdown ?? this.replyMarkdown,
    suggestions: suggestions ?? this.suggestions,
  );

  /// Sérialise la réponse en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'reply': replyMarkdown,
    'suggestions': <Map<String, Object?>>[
      for (final item in suggestions) item.toJson(),
    ],
  };

  /// Désérialise une réponse depuis JSON.
  factory BackendAiTurnResponse.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('BackendAiTurnResponse invalide.');
    }
    final reply =
        (raw['reply'] ?? raw['replyMarkdown'] ?? raw['message'])?.toString() ??
        '';
    final parsedSuggestions = <BackendAiSuggestion>[];
    if (raw['suggestions'] case final List list) {
      for (final item in list) {
        try {
          parsedSuggestions.add(BackendAiSuggestion.fromJson(item));
        } on FormatException {
          // Ignore les éléments malformés pour préserver la robustesse du flux.
        }
      }
    }
    return BackendAiTurnResponse(
      replyMarkdown: reply,
      suggestions: parsedSuggestions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackendAiTurnResponse &&
          other.replyMarkdown == replyMarkdown &&
          listEquals(other.suggestions, suggestions);

  @override
  int get hashCode => Object.hash(replyMarkdown, Object.hashAll(suggestions));
}

/// Analyseur tolérant des réponses générées par l'assistant IA Backend.
///
/// Supporte indifféremment :
/// * un objet JSON strict `{"reply": "...", "suggestions": [...]}` ;
/// * un bloc de code Markdown ```` ```json ... ``` ```` entouré ou non de texte ;
/// * un repli Markdown libre sans jamais lever d'exception.
abstract final class BackendAiResponseParser {
  static final RegExp _fencedBlockPattern = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  );

  /// Analyse [rawText] et retourne toujours une [BackendAiTurnResponse] valide.
  static BackendAiTurnResponse parse(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return BackendAiTurnResponse(replyMarkdown: '');
    }

    final direct = _tryParseJsonEnvelope(trimmed);
    if (direct != null) {
      return direct;
    }

    for (final match in _fencedBlockPattern.allMatches(trimmed)) {
      final candidate = (match.group(1) ?? '').trim();
      if (candidate.isEmpty) continue;
      final fromFence = _tryParseJsonEnvelope(candidate);
      if (fromFence != null) {
        if (fromFence.replyMarkdown.trim().isNotEmpty) {
          return fromFence;
        }
        final surrounding = trimmed
            .replaceRange(match.start, match.end, '')
            .trim();
        return fromFence.copyWith(
          replyMarkdown: surrounding.isNotEmpty ? surrounding : candidate,
        );
      }
    }

    final embeddedJson = _extractFirstBalancedJsonObject(trimmed);
    if (embeddedJson != null) {
      final fromEmbedded = _tryParseJsonEnvelope(embeddedJson.jsonText);
      if (fromEmbedded != null) {
        if (fromEmbedded.replyMarkdown.trim().isNotEmpty) {
          return fromEmbedded;
        }
        final prefix = trimmed.substring(0, embeddedJson.start).trim();
        final suffix = trimmed.substring(embeddedJson.end).trim();
        final surrounding = <String>[
          if (prefix.isNotEmpty) prefix,
          if (suffix.isNotEmpty) suffix,
        ].join('\n\n');
        return fromEmbedded.copyWith(replyMarkdown: surrounding);
      }
    }

    return BackendAiTurnResponse(replyMarkdown: trimmed);
  }

  static BackendAiTurnResponse? _tryParseJsonEnvelope(String jsonCandidate) {
    if (!jsonCandidate.startsWith('{')) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonCandidate);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final hasEnvelopeKey =
        decoded.containsKey('reply') ||
        decoded.containsKey('replyMarkdown') ||
        decoded.containsKey('message') ||
        decoded.containsKey('suggestions');
    if (!hasEnvelopeKey) return null;
    return BackendAiTurnResponse.fromJson(decoded);
  }

  static ({String jsonText, int start, int end})?
  _extractFirstBalancedJsonObject(String text) {
    final firstBrace = text.indexOf('{');
    if (firstBrace < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    var startIndex = -1;

    for (var i = firstBrace; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        if (depth == 0) startIndex = i;
        depth++;
      } else if (ch == '}') {
        if (depth > 0) {
          depth--;
          if (depth == 0 && startIndex >= 0) {
            return (
              jsonText: text.substring(startIndex, i + 1),
              start: startIndex,
              end: i + 1,
            );
          }
        }
      }
    }
    return null;
  }
}

/// Interface injectable et mockable de l'assistant IA de `super_backend_editor`.
abstract interface class BackendEditorAiService {
  /// Diffuse en flux SSE ([GeminiStreamEvent]) la réponse d'assistance pour
  /// [userMessage] contextualisée sur [project].
  Stream<GeminiStreamEvent> streamAssistantTurn({
    required BackendDomainProject project,
    required String userMessage,
    BackendAiTaskKind taskKind = BackendAiTaskKind.generalAssistant,
    String? focusedTargetId,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<Map<String, Object?>>? conversationContents,
  });

  /// Préchauffe silencieusement la connexion TLS et le cache de contexte Gemini.
  Future<void> warmUp({VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast});
}

/// Implémentation de [BackendEditorAiService] appuyée sur `streamGemini` et
/// `warmUpGemini` de `super_container_layout`.
class GeminiBackendEditorAiService implements BackendEditorAiService {
  /// Crée le service IA Gemini pour `super_backend_editor`.
  const GeminiBackendEditorAiService();

  /// Construit l'instruction système française adaptée à [taskKind].
  static String buildSystemInstruction([
    BackendAiTaskKind taskKind = BackendAiTaskKind.generalAssistant,
  ]) {
    final taskFocus = switch (taskKind) {
      BackendAiTaskKind.generalAssistant =>
        'Réponds de façon précise et actionnable aux questions sur le domaine, '
            'les invariants DDD, les Use Cases CQRS, les endpoints REST et les '
            'collections `super_backend`.',
      BackendAiTaskKind.generateQuickJsHandler =>
        'Concentre-toi sur l’écriture de scripts JavaScript QuickJS propres, '
            'déterministes et conformes aux invariants de la couche Domain '
            'hexagonale, aux scénarios Given/When/Then du Use Case ciblé et '
            'au contrat exact de l’objet global `ctx`.',
      BackendAiTaskKind.generateSeedEntities =>
        'Concentre-toi sur la génération d’entités JSON réalistes, cohérentes '
            'entre elles (clés primaires, clés étrangères, dates ISO-8601, '
            'énumérations et invariants métier) et strictement valides vis-à-vis '
            'du JSON Schema Draft 2020-12 de la collection ciblée.',
      BackendAiTaskKind.diagnoseCoherenceOrError =>
        'Analyse méthodiquement les écarts entre la spécification Design en '
            'lecture seule et la surcouche Backend locale (ou l’erreur runtime '
            'soumise), explique la cause racine et propose les correctifs précis.',
    };

    return '''
Tu es l'architecte et développeur Backend expert intégré à `super_backend_editor` (Architecture Hexagonale, DDD, CQRS, Sagas, SQLite SCRUD `super_backend` et runtime JavaScript QuickJS).
Tu t'exprimes toujours en français clair, concis et rigoureux.

RÈGLE D'ARCHITECTURE FONDAMENTALE :
- La couche Design (`DomainDesignSpec` issue de `super_spec_forge`) est STRICTEMENT EN LECTURE SEULE : ne propose jamais de la modifier directement, implémente toujours la logique et l'exposition dans l'overlay Backend (`collections`, `endpoints`, `scripts` QuickJS, données de seed et payloads de test).
- Sécurité : n'invente et n'expose jamais de valeur secrète en clair ; lis toujours les secrets et configurations d'environnement via `ctx.env("NOM_CLE")`.

OBJECTIF PRIORITAIRE DU TOUR (${taskKind.name}) :
$taskFocus
''';
  }

  /// Retourne le guide statique décrivant l'API QuickJS `ctx` et le schéma JSON
  /// de réponse attendu (mis en cache côté Gemini).
  static String buildStaticRuntimeGuide() => r'''
# CONTRAT D'EXÉCUTION QUICKJS (`ctx`) DANS `super_backend_editor`

Chaque script QuickJS (invariant de modèle, commande d'agrégat, Use Case CQRS, Saga ou endpoint personnalisé) s'exécute avec l'objet global `ctx` exposant exactement les membres suivants :

1. **Entrées de la requête / commande** :
   - `ctx.input` : objet JSON du corps reçu (`POST`/`PUT`/`PATCH`) ou de l'entité validée.
   - `ctx.params` : objet `{ [nomParam]: string }` des paramètres extraits du chemin d'URL.
   - `ctx.query` : objet `{ [cle]: string }` des paramètres de query string HTTP.
   - `ctx.env(key)` : retourne la valeur `string | null` de la variable d'environnement ou du secret configuré pour l'environnement actif du domaine.

2. **Accès SCRUD aux collections persistantes `super_backend`** :
   - `ctx.collection(name).search(params)` : recherche filtrée/triée/paginée retournant `{ items: [...], total, page, pageSize }`.
   - `ctx.collection(name).read(id)` : lit une entité par son identifiant (ou `null` si absente).
   - `ctx.collection(name).create(data)` : crée et valide une nouvelle entité JSON et la retourne.
   - `ctx.collection(name).update(id, patch)` : met à jour partiellement l'entité `id` et retourne l'entité mise à jour.
   - `ctx.collection(name).delete(id)` : supprime l'entité `id` selon la politique de suppression (`hardDelete`, `softDelete`, `immutableArchive`).

3. **Événements métier & assertions d'invariants** :
   - `ctx.emit(eventName, payload)` : publie un événement métier du domaine (ex. `"InvoiceApproved"`).
   - `ctx.assert(cond, message)` : vérifie une précondition ou un invariant DDD ; si `cond` est faux, interrompt immédiatement l'exécution avec une erreur métier explicite portant `message`.

4. **Valeur de retour d'un script** :
   - Retourne un objet JSON sérialisable (ou `export default function handle(ctx) { ... }` / expression finale retournant le résultat JSON).

---

# FORMAT DE RÉPONSE JSON OBLIGATOIRE

Réponds UNIQUEMENT par un objet JSON valide (sans texte hors du JSON) respectant exactement cette structure :

{
  "reply": "Explication claire et structurée en Markdown français...",
  "suggestions": [
    {
      "kind": "quickjs_script",
      "targetId": "usecases/uc_example.js",
      "title": "Titre court du script ou de l'action",
      "codeOrJson": "// Code JavaScript QuickJS utilisant ctx...",
      "entities": []
    },
    {
      "kind": "seed_entities",
      "targetId": "invoices",
      "title": "Jeu d'entités initiales pour invoices",
      "codeOrJson": "[ ... ]",
      "entities": [
        { "id": "inv_001", "...": "..." }
      ]
    },
    {
      "kind": "endpoint_payload",
      "targetId": "ep_uc_create_invoice",
      "title": "Payload d'exemple pour tester l'endpoint",
      "codeOrJson": "{\n  \"customerId\": \"cust_001\"\n}",
      "entities": []
    }
  ]
}

Règles sur `"suggestions"` :
- `"kind"` vaut exclusivement `"quickjs_script"`, `"seed_entities"` ou `"endpoint_payload"`.
- Si aucune suggestion d'artefact n'est pertinente, retourne `"suggestions": []`.
- Pour `"seed_entities"`, renseigne toujours le tableau d'objets JSON dans `"entities"` (et sa représentation JSON dans `"codeOrJson"`), avec dates au format ISO-8601 (`"YYYY-MM-DD"` ou `"YYYY-MM-DDTHH:MM:SSZ"`).
''';

  /// Construit le prompt utilisateur enrichi du résumé structuré de [project].
  static String buildDomainContextPrompt({
    required BackendDomainProject project,
    required String userMessage,
    BackendAiTaskKind taskKind = BackendAiTaskKind.generalAssistant,
    String? focusedTargetId,
  }) {
    final spec = project.designSpec;
    final overlay = project.overlay;
    final buf = StringBuffer();

    buf.writeln('## CONTEXTE DU DOMAINE MÉTIER');
    buf.writeln(
      '- Domaine : **${spec.domain.name}** (`${spec.domain.domainCode}`)',
    );
    if (spec.domain.description.trim().isNotEmpty) {
      buf.writeln('- Description : ${spec.domain.description.trim()}');
    }
    if (spec.domain.techStack != null) {
      buf.writeln(
        '- Stack Design : ${spec.domain.techStack!.name} (`${spec.domain.techStack!.code}`)',
      );
    }
    buf.writeln(
      '- Serveur local : `${overlay.server.baseUrl}` '
      '(host `${overlay.server.host}`, port `${overlay.server.port}`, apiPrefix `${overlay.server.apiPrefix}`)',
    );

    final activeEnvId =
        overlay.activeEnvironmentId ?? spec.environments.firstOrNull?.id;
    if (activeEnvId != null) {
      final envKeys = <String>[];
      for (final cfg in spec.configurations) {
        if (cfg.environmentId != activeEnvId) continue;
        if (cfg.isSecret) {
          envKeys.add('${cfg.configKey} [SECRET via ctx.env]');
        } else {
          envKeys.add('${cfg.configKey}="${cfg.plainValue ?? ''}"');
        }
      }
      if (envKeys.isNotEmpty) {
        buf.writeln(
          '- Clés de configuration (`$activeEnvId`) : ${envKeys.join(', ')}',
        );
      }
    }

    if (spec.valueObjects.isNotEmpty) {
      buf.writeln('\n## VALUE OBJECTS (${spec.valueObjects.length})');
      for (final vo in spec.valueObjects) {
        final typeDesc = vo.isScalar
            ? 'scalar(${vo.primitiveType ?? 'string'})'
            : 'composite(${vo.fields.map((f) => f['name'] ?? f['technicalName'] ?? '').where((s) => '$s'.isNotEmpty).join(', ')})';
        final exSummary = vo.examples.isNotEmpty
            ? ' — exemples: ${vo.examples.take(2).map((e) => '${e['value']} (${e['isValid'] == false ? 'invalide' : 'valide'})').join('; ')}'
            : '';
        buf.writeln(
          '- `${vo.technicalName}` (${vo.name}, ${vo.scope}) : $typeDesc'
          '${vo.description.trim().isNotEmpty ? ' — ${vo.description.trim()}' : ''}$exSummary',
        );
      }
    }

    if (spec.models.isNotEmpty) {
      buf.writeln(
        '\n## MODÈLES PERSISTANTS & COUCHE DOMAIN HEXAGONALE (7 ONGLETS) (${spec.models.length})',
      );
      for (final model in spec.models) {
        buf.writeln(
          '### Modèle `${model.technicalName}` (`entryId`: `${model.entryId}`, label: ${model.effectiveLabel})',
        );
        if (model.description.trim().isNotEmpty) {
          buf.writeln('  - Description : ${model.description.trim()}');
        }
        final attrList = _summarizeModelAttributes(model);
        if (attrList.isNotEmpty) {
          buf.writeln('  - Attributs : ${attrList.join(', ')}');
        }
        if (model.invariants.isNotEmpty) {
          buf.writeln(
            '  - [1. Invariants] : ${_summarizeNamedItems(model.invariants)}',
          );
        }
        if (model.stateChangingMethods.isNotEmpty) {
          buf.writeln(
            '  - [2. Commandes d’agrégat (State changing)] : ${_summarizeNamedItems(model.stateChangingMethods)}',
          );
        }
        if (model.queryMethods.isNotEmpty) {
          buf.writeln(
            '  - [3. Méthodes Query pures] : ${_summarizeNamedItems(model.queryMethods)}',
          );
        }
        if (model.policyServices.isNotEmpty) {
          buf.writeln(
            '  - [4. Policy Services] : ${_summarizeNamedItems(model.policyServices)}',
          );
        }
        if (model.factories.isNotEmpty) {
          buf.writeln(
            '  - [5. Factories] : ${_summarizeNamedItems(model.factories)}',
          );
        }
        if (model.domainEvents.isNotEmpty) {
          buf.writeln(
            '  - [6. Domain Events] : ${_summarizeNamedItems(model.domainEvents)}',
          );
        }
        if (model.domainLayerJson['persistencePolicy'] is Map ||
            model.domainLayerJson['persistence_policy_behaviors'] is Map) {
          final policy = model.persistencePolicy;
          buf.writeln(
            '  - [7. Persistence Policy] : port `${policy['repositoryPortName']}`, '
            'concurrence `${policy['concurrencyStrategy']}`, '
            'suppression `${policy['deletionStrategy']}`',
          );
        }
      }
    }

    if (spec.useCases.isNotEmpty) {
      buf.writeln(
        '\n## USE CASES CQRS & SCÉNARIOS GIVEN/WHEN/THEN (${spec.useCases.length})',
      );
      for (final uc in spec.useCases) {
        buf.writeln(
          '### `${uc.code}` — ${uc.effectiveTitle} (`id`: `${uc.id}`, type: `${uc.cqrsType.toUpperCase()}`, agrégat: `${uc.targetAggregate}`)',
        );
        if (uc.businessGoal.trim().isNotEmpty) {
          buf.writeln('  - Objectif : ${uc.businessGoal.trim()}');
        }
        if (uc.businessRules.isNotEmpty) {
          buf.writeln('  - Règles métier : ${uc.businessRules.join(' | ')}');
        }
        if (uc.emittedEvents.isNotEmpty) {
          buf.writeln('  - Événements émis : ${uc.emittedEvents.join(', ')}');
        }
        if (uc.possibleErrors.isNotEmpty) {
          buf.writeln(
            '  - Erreurs possibles : ${uc.possibleErrors.join(' | ')}',
          );
        }
        if (uc.scenarios.isNotEmpty) {
          for (final sc in uc.scenarios.take(5)) {
            final scTitle =
                (sc['title'] ?? sc['name'] ?? sc['id'] ?? 'Scénario')
                    .toString();
            final given = sc['given'] ?? sc['preconditions'] ?? '';
            final whenClause = sc['when'] ?? sc['action'] ?? '';
            final thenClause = sc['then'] ?? sc['expected'] ?? '';
            buf.writeln(
              '  - Scénario « $scTitle » : Given [$given] -> When [$whenClause] -> Then [$thenClause]',
            );
          }
        }
      }
    }

    if (spec.sagas.isNotEmpty) {
      buf.writeln('\n## SAGAS DISTRIBUÉES (${spec.sagas.length})');
      for (final saga in spec.sagas) {
        buf.writeln(
          '- `${saga.code}` ${saga.name} (`id`: `${saga.id}`, mode: `${saga.coordinationMode}`, trigger: `${saga.triggerEvent}`, étapes: ${saga.steps.length})',
        );
      }
    }

    buf.writeln('\n## OVERLAY BACKEND LOCAL');
    buf.writeln(
      '### Collections `super_backend` (${overlay.collections.length})',
    );
    for (final col in overlay.collections) {
      buf.writeln(
        '- `${col.collectionName}` (id: `${col.id}`, label: ${col.label}, '
        'enabled: ${col.enabled}, keyField: `${col.keyField}`, '
        'deletion: `${col.deletionMode.name}`, concurrency: `${col.concurrencyMode.name}`'
        '${col.invariantScriptPath != null ? ', invariantScript: `${col.invariantScriptPath}`' : ''})',
      );
    }

    buf.writeln('### Endpoints HTTP (${overlay.endpoints.length})');
    for (final ep in overlay.endpoints) {
      buf.writeln(
        '- `${ep.id}` : `${ep.method} ${ep.path}` (${ep.kind.name}, enabled: ${ep.enabled}'
        '${ep.useCaseId != null ? ', useCaseId: `${ep.useCaseId}`' : ''}'
        '${ep.collectionId != null ? ', collectionId: `${ep.collectionId}`' : ''}'
        '${ep.handlerScriptPath != null ? ', handler: `${ep.handlerScriptPath}`' : ''})',
      );
    }

    if (overlay.scripts.isNotEmpty) {
      buf.writeln(
        '### Liaisons de scripts QuickJS (${overlay.scripts.length})',
      );
      for (final sb in overlay.scripts) {
        buf.writeln(
          '- `${sb.scriptPath}` (${sb.targetKind.name} -> `${sb.targetId}`, enabled: ${sb.enabled})',
        );
      }
    }

    final cleanFocus = focusedTargetId?.trim();
    if (cleanFocus != null && cleanFocus.isNotEmpty) {
      buf.writeln('\n## CIBLE FOCALISÉE POUR CE TOUR : `$cleanFocus`');
      _appendFocusedTargetDetails(buf, project, cleanFocus);
    }

    buf.writeln('\n## TÂCHE DEMANDÉE (${taskKind.label})');
    buf.writeln(userMessage.trim());
    return buf.toString();
  }

  static List<String> _summarizeModelAttributes(ImportedContractEntry model) {
    final out = <String>[];
    final schemaProps = model.jsonSchema['properties'];
    final requiredSet = <String>{
      if (model.jsonSchema['required'] case final List req)
        for (final r in req) '$r',
    };
    if (schemaProps is Map && schemaProps.isNotEmpty) {
      for (final entry in schemaProps.entries) {
        final key = '${entry.key}';
        final prop = entry.value;
        var typeDesc = 'any';
        if (prop is Map) {
          typeDesc = '${prop['type'] ?? 'object'}';
          if (prop['format'] != null) {
            typeDesc = '$typeDesc(${prop['format']})';
          } else if (prop['enum'] is List) {
            typeDesc = '$typeDesc${prop['enum']}';
          }
        }
        out.add('$key: $typeDesc${requiredSet.contains(key) ? '*' : ''}');
      }
      return out;
    }
    for (final attr in model.attributes) {
      final name = (attr['technicalName'] ?? attr['name']) ?? '';
      final type = (attr['type'] ?? attr['dataType']) ?? 'string';
      final req = attr['required'] == true ? '*' : '';
      if ('$name'.trim().isNotEmpty) {
        out.add('$name: $type$req');
      }
    }
    return out;
  }

  static String _summarizeNamedItems(List<Map<String, Object?>> items) {
    final parts = <String>[];
    for (final item in items.take(8)) {
      final name =
          (item['name'] ??
                  item['code'] ??
                  item['title'] ??
                  item['eventName'] ??
                  item['id'] ??
                  'Règle')
              .toString()
              .trim();
      final desc =
          (item['description'] ??
                  item['rule'] ??
                  item['expression'] ??
                  item['summary'] ??
                  '')
              .toString()
              .trim();
      parts.add(desc.isNotEmpty ? '$name ($desc)' : name);
    }
    return parts.join(' ; ');
  }

  static void _appendFocusedTargetDetails(
    StringBuffer buf,
    BackendDomainProject project,
    String target,
  ) {
    final spec = project.designSpec;
    final overlay = project.overlay;

    for (final col in overlay.collections) {
      if (col.collectionName == target || col.id == target) {
        final model = col.contractEntryId != null
            ? spec.findContractById(col.contractEntryId!)
            : null;
        if (model != null && model.jsonSchema.isNotEmpty) {
          buf.writeln(
            'JSON Schema complet de la collection `${col.collectionName}` :\n'
            '```json\n${_prettyJson.convert(model.jsonSchema)}\n```',
          );
        }
      }
    }

    for (final ep in overlay.endpoints) {
      if (ep.id == target ||
          ep.path == target ||
          ep.handlerScriptPath == target) {
        final uc = ep.useCaseId != null
            ? spec.findUseCaseById(ep.useCaseId!)
            : null;
        if (uc != null) {
          if (uc.inputJsonSchema.isNotEmpty) {
            buf.writeln(
              'Input JSON Schema de `${uc.code}` :\n'
              '```json\n${_prettyJson.convert(uc.inputJsonSchema)}\n```',
            );
          }
          if (uc.outputJsonSchema.isNotEmpty) {
            buf.writeln(
              'Output JSON Schema de `${uc.code}` :\n'
              '```json\n${_prettyJson.convert(uc.outputJsonSchema)}\n```',
            );
          }
        }
      }
    }

    final directUc = spec.findUseCaseById(target);
    if (directUc != null) {
      if (directUc.inputJsonSchema.isNotEmpty) {
        buf.writeln(
          'Input JSON Schema de `${directUc.code}` :\n'
          '```json\n${_prettyJson.convert(directUc.inputJsonSchema)}\n```',
        );
      }
      if (directUc.outputJsonSchema.isNotEmpty) {
        buf.writeln(
          'Output JSON Schema de `${directUc.code}` :\n'
          '```json\n${_prettyJson.convert(directUc.outputJsonSchema)}\n```',
        );
      }
    }
  }

  @override
  Stream<GeminiStreamEvent> streamAssistantTurn({
    required BackendDomainProject project,
    required String userMessage,
    BackendAiTaskKind taskKind = BackendAiTaskKind.generalAssistant,
    String? focusedTargetId,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    List<Map<String, Object?>>? conversationContents,
  }) {
    final prompt = buildDomainContextPrompt(
      project: project,
      userMessage: userMessage,
      taskKind: taskKind,
      focusedTargetId: focusedTargetId,
    );
    return streamGemini(
      prompt,
      systemInstruction: buildSystemInstruction(taskKind),
      staticGuide: buildStaticRuntimeGuide(),
      attachments: attachments,
      speedMode: speedMode,
      conversationContents: conversationContents,
      enforceJsonResponse: true,
    );
  }

  @override
  Future<void> warmUp({VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast}) =>
      warmUpGemini(
        systemInstruction: buildSystemInstruction(),
        staticGuide: buildStaticRuntimeGuide(),
        speedMode: speedMode,
      );
}
