/// Contrats de déclaration, appel et résultat d'outils ([VibeAppToolRegistry]) pour Vibe IA.
///
/// Fournit une abstraction découplée des widgets pour déclarer des outils
/// d'introspection en lecture seule utilisables à la fois via le Function
/// Calling natif Gemini (`functionDeclarations`) et via le protocole JSON
/// unifié `"toolCalls"` dans les réponses Vibe.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, mapEquals;

import 'vibe_chat_attachment.dart';

/// Déclaration d'un outil exposé à l'assistant Vibe IA.
@immutable
class VibeToolDeclaration {
  /// Crée une déclaration d'outil avec son schéma JSON Schema des paramètres.
  const VibeToolDeclaration({
    required this.name,
    required this.description,
    required this.parametersSchema,
  });

  /// Nom technique unique de l'outil (snake_case, ex. `get_component_geometry`).
  final String name;

  /// Description concise expliquant à l'IA quand et comment utiliser cet outil.
  final String description;

  /// Schéma JSON Schema (type `object`) décrivant les paramètres acceptés.
  final Map<String, Object?> parametersSchema;

  /// Sérialise cette déclaration au format `functionDeclarations` de l'API Gemini `v1beta`.
  Map<String, Object?> toGeminiFunctionDeclaration() => <String, Object?>{
    'name': name,
    'description': description,
    'parameters': parametersSchema,
  };
}

/// Appel d'outil demandé par le modèle IA (natif `functionCall` ou JSON `"toolCalls"`).
@immutable
class VibeToolCall {
  /// Crée un appel d'outil.
  VibeToolCall({
    required this.id,
    required this.name,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) : arguments = Map<String, Object?>.unmodifiable(arguments);

  /// Tente de parser un objet JSON provenant du champ `"toolCalls"` d'une réponse Vibe.
  static VibeToolCall? tryFromJson(Object? raw, {int fallbackIndex = 0}) {
    if (raw is! Map) return null;
    final rawName = raw['name'];
    if (rawName is! String || rawName.trim().isEmpty) return null;
    final rawId = raw['id'];
    final id = rawId is String && rawId.trim().isNotEmpty
        ? rawId.trim()
        : 'tool_call_$fallbackIndex';
    final rawArgs = raw['arguments'] ?? raw['args'];
    final args = <String, Object?>{};
    if (rawArgs is Map) {
      for (final entry in rawArgs.entries) {
        if (entry.key is String) {
          args[entry.key as String] = entry.value;
        }
      }
    }
    return VibeToolCall(id: id, name: rawName.trim(), arguments: args);
  }

  /// Parse une liste éventuelle d'appels d'outils depuis `"toolCalls"`.
  static List<VibeToolCall> tryListFromJson(Object? raw) {
    if (raw is! List) return const <VibeToolCall>[];
    final calls = <VibeToolCall>[];
    for (var i = 0; i < raw.length; i++) {
      final parsed = tryFromJson(raw[i], fallbackIndex: i);
      if (parsed != null) {
        calls.add(parsed);
      }
    }
    return List<VibeToolCall>.unmodifiable(calls);
  }

  /// Identifiant de corrélation de l'appel (utile pour les journaux et le format JSON).
  final String id;

  /// Nom de l'outil appelé.
  final String name;

  /// Arguments JSON transmis par le modèle.
  final Map<String, Object?> arguments;

  /// Sérialise l'appel au format `functionCall` Gemini.
  Map<String, Object?> toGeminiFunctionCall() => <String, Object?>{
    'name': name,
    'args': arguments,
  };

  /// Sérialise l'appel au format JSON générique.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'arguments': arguments,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeToolCall &&
          other.id == id &&
          other.name == name &&
          mapEquals(other.arguments, arguments);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(arguments.keys));
}

/// Résultat structuré retourné par l'exécution locale d'un [VibeToolCall].
@immutable
class VibeToolResult {
  /// Crée un résultat d'outil.
  VibeToolResult({
    required this.callId,
    required this.name,
    Map<String, Object?> data = const <String, Object?>{},
    this.isError = false,
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
  }) : data = Map<String, Object?>.unmodifiable(data),
       attachments = List<VibeChatAttachment>.unmodifiable(attachments);

  /// Construit un résultat d'erreur structuré sans lever d'exception vers le modèle.
  factory VibeToolResult.error({
    required String callId,
    required String name,
    required String message,
  }) => VibeToolResult(
    callId: callId,
    name: name,
    isError: true,
    data: <String, Object?>{'ok': false, 'error': message},
  );

  /// Identifiant de corrélation de l'appel correspondant.
  final String callId;

  /// Nom de l'outil exécuté.
  final String name;

  /// Indique si l'exécution a échoué (outil inconnu, argument invalide, cible absente).
  final bool isError;

  /// Charge JSON structurée retournée au modèle.
  final Map<String, Object?> data;

  /// Pièces jointes éventuelles produites par l'outil (ex. capture PNG).
  final List<VibeChatAttachment> attachments;

  /// Formate la réponse au format attendu par Gemini `functionResponse.response`.
  Map<String, Object?> toGeminiFunctionResponsePayload() => <String, Object?>{
    'ok': !isError,
    ...data,
  };

  /// Sérialise le résultat complet pour le journal de tour ou le protocole JSON unifié.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': callId,
    'name': name,
    'ok': !isError,
    'result': data,
    if (attachments.isNotEmpty)
      'attachments': [
        for (final a in attachments)
          <String, Object?>{'name': a.name, 'mimeType': a.mimeType},
      ],
  };
}

/// Trace synthétique d'un appel d'outil exécuté, affichée dans l'historique du chat.
@immutable
class VibeToolTrace {
  /// Crée une trace immuable d'appel d'outil.
  VibeToolTrace({
    required this.name,
    Map<String, Object?> arguments = const <String, Object?>{},
    this.isError = false,
    this.summary = '',
    this.isPostVerify = false,
  }) : arguments = Map<String, Object?>.unmodifiable(arguments);

  /// Construit une trace synthétique à partir d'un [call] et de son [result].
  factory VibeToolTrace.fromExecution(
    VibeToolCall call,
    VibeToolResult result, {
    bool isPostVerify = false,
  }) => VibeToolTrace(
    name: call.name,
    arguments: call.arguments,
    isError: result.isError,
    summary: _summarize(call, result),
    isPostVerify: isPostVerify,
  );

  /// Nom de l'outil exécuté.
  final String name;

  /// Arguments transmis lors de l'appel.
  final Map<String, Object?> arguments;

  /// Indique si l'exécution s'est terminée en erreur.
  final bool isError;

  /// Résumé lisible en une ligne du résultat obtenu.
  final String summary;

  /// Indique si cet appel a eu lieu durant la passe d'auto-vérification post-rendu.
  final bool isPostVerify;

  static String _summarize(VibeToolCall call, VibeToolResult result) {
    final data = result.data;
    if (result.isError) {
      final err = data['error'];
      return err is String && err.trim().isNotEmpty ? err.trim() : 'Erreur';
    }
    switch (call.name) {
      case 'get_component_geometry':
        final comps = data['components'];
        if (comps is Map && comps.isNotEmpty) {
          final parts = <String>[];
          for (final entry in comps.entries) {
            final val = entry.value;
            if (val is Map) {
              if (val['mounted'] == false) {
                parts.add('${entry.key}: non monté');
              } else if (val['occurrences'] case final List occs
                  when occs.isNotEmpty && occs.first is Map) {
                final firstOcc = occs.first as Map;
                final size = firstOcc['size'];
                if (size is Map) {
                  parts.add(
                    '${entry.key}: ${_fmtNum(size['width'])}×${_fmtNum(size['height'])} dp',
                  );
                  continue;
                }
              }
            }
            if (parts.length < 3) parts.add('${entry.key}');
          }
          if (parts.isNotEmpty) return parts.take(3).join(', ');
        }
      case 'get_viewport_and_route':
        final vp = data['viewport'];
        final route = data['route'];
        final vpText = vp is Map
            ? '${_fmtNum(vp['width'])}×${_fmtNum(vp['height'])} dp'
            : null;
        final loc = route is Map ? route['location'] as String? : null;
        if (vpText != null && loc != null && loc.isNotEmpty) {
          return '$vpText ($loc)';
        }
        if (vpText != null) return vpText;
      case 'get_runtime_tree':
        final rootId = data['rootId'];
        if (rootId is String && rootId.isNotEmpty) {
          return 'racine $rootId${data['truncated'] == true ? ' (tronqué)' : ''}';
        }
      case 'query_repository_data':
        final repoId = data['id'] ?? call.arguments['repositoryId'];
        final path = data['path'] ?? call.arguments['path'];
        if (repoId is String && repoId.isNotEmpty) {
          return path is String && path.isNotEmpty ? '$repoId.$path' : repoId;
        }
        final count = data['repositoryCount'];
        if (count is num) return '$count repository(s)';
      case 'manage_repository_json_schema':
        final action = data['action'] ?? call.arguments['action'] ?? '';
        final repoId =
            data['id'] ?? data['name'] ?? call.arguments['repositoryId'] ?? '';
        if (action == 'validate') {
          final valid = data['valid'] == true;
          final issueCount = data['issueCount'] ?? 0;
          return valid
              ? '$repoId : conforme'
              : '$repoId : $issueCount erreur(s)';
        }
        return '$action $repoId'.trim();
      case 'capture_element_screenshot':
      case 'capture_screenshot':
        final target = data['target'] ?? data['componentId'] ?? 'viewport';
        final w = data['logicalWidth'];
        final h = data['logicalHeight'];
        final occ = data['occurrenceIndex'];
        final occSuffix = (occ is int && occ > 0) ? ' [#$occ]' : '';
        if (w != null && h != null) {
          return '$target$occSuffix (${_fmtNum(w)}×${_fmtNum(h)} dp)';
        }
        return '$target$occSuffix';
      case 'get_debug_entries':
        final returned = data['returnedCount'];
        final turnErrs = data['turnErrorCount'];
        if (turnErrs is int && turnErrs > 0) {
          return '$returned entrée(s), $turnErrs erreur(s) sur ce tour';
        }
        return '${returned ?? 0} entrée(s) (${data['totalErrors'] ?? 0} erreur(s) au total)';
      case 'get_datasources_and_providers':
        return '${data['datasourceCount'] ?? 0} datasource(s), '
            '${data['providerCount'] ?? 0} provider(s)';
      case 'inspect_bindings_and_diagnostics':
        final issues = data['issueCount'] ?? 0;
        final orphans = data['orphanComponentCount'] ?? 0;
        return '$issues alerte(s) sur ${data['checkedBindings'] ?? 0} liaison(s)'
            '${orphans is int && orphans > 0 ? ', $orphans orphelin(s)' : ''}';
      case 'get_theme_and_contrast':
        final issues = data['contrastIssueCount'] ?? 0;
        final mode = data['effectiveBrightness'] ?? data['mode'] ?? '';
        return 'thème $mode — $issues alerte(s) contraste AA';
      case 'get_registry_and_selection':
        final count = data['registeredBuilderCount'];
        return count is num ? '$count type(s) dans Registry' : 'sélection lue';
      case 'preview_navigation_or_selection':
        final nav = data['navigatedTo'];
        final sel = data['selection'];
        if (nav is String && sel is Map) {
          return 'route $nav + sélection ${sel['arrayTemplate']}';
        }
        if (nav is String) return 'route $nav';
        if (sel is Map) {
          return '${sel['repositoryId']}:${sel['arrayTemplate']} → ${sel['selection'] ?? 'aucune'}';
        }
        return 'aperçu mis à jour';
      case 'select_editor_element':
        if (data['cleared'] == true) return 'sélection effacée';
        final cid = data['componentId'] ?? '';
        final zid = data['zoneId'];
        final lbl = data['label'];
        final base = zid is String && zid.isNotEmpty ? '$cid::$zid' : '$cid';
        return lbl is String && lbl.isNotEmpty && lbl != cid
            ? '$base ($lbl)'
            : base;
      case 'register_design_system':
        final name = data['name'] ?? data['id'] ?? 'DESIGN.md';
        final selected = data['selected'] == true ? ' (activé)' : '';
        return '$name ajouté$selected';
      case 'audit_active_page':
        final count = data['findingCount'] ?? 0;
        final errors = data['errorCount'] ?? 0;
        return '$count anomalie(s) détectée(s) ($errors critique(s))';
    }
    return 'OK';
  }

  static String _fmtNum(Object? v) {
    if (v is num) {
      return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    }
    return '$v';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeToolTrace &&
          other.name == name &&
          other.isError == isError &&
          other.summary == summary &&
          other.isPostVerify == isPostVerify &&
          mapEquals(other.arguments, arguments);

  @override
  int get hashCode =>
      Object.hash(name, isError, summary, isPostVerify, arguments.length);
}

/// Fonction d'exécution asynchrone d'un outil enregistré dans [VibeAppToolRegistry].
typedef VibeToolHandler = Future<VibeToolResult> Function(VibeToolCall call);

/// Entrée associant une [VibeToolDeclaration] et son [VibeToolHandler].
@immutable
class VibeRegisteredTool {
  /// Crée une entrée d'outil exécutable.
  const VibeRegisteredTool({required this.declaration, required this.handler});

  /// Métadonnées et schéma JSON Schema exposés à l'IA.
  final VibeToolDeclaration declaration;

  /// Implémentation locale exécutée sur l'application.
  final VibeToolHandler handler;
}

/// Registre des outils d'introspection exposés à Vibe IA.
class VibeAppToolRegistry {
  /// Crée un registre à partir d'une liste de [VibeRegisteredTool].
  VibeAppToolRegistry(Iterable<VibeRegisteredTool> tools) {
    for (final tool in tools) {
      _tools[tool.declaration.name] = tool;
    }
  }

  /// Registre vide ne déclarant aucun outil.
  static final VibeAppToolRegistry empty = VibeAppToolRegistry(const []);

  /// Déclarations standard des 5 outils d'introspection en lecture seule.
  static const List<VibeToolDeclaration> standardDeclarations =
      <VibeToolDeclaration>[
        VibeToolDeclaration(
          name: 'get_viewport_and_route',
          description:
              'Retourne la taille réelle de la fenêtre/viewport en dp, le devicePixelRatio, '
              'la route GoRouter active, la page active du catalogue, le mode édition et le scope.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
        VibeToolDeclaration(
          name: 'get_component_geometry',
          description:
              'Mesure la géométrie réelle rendue à l’écran (taille width/height en dp, '
              'position globale et relative au parent, contraintes de layout, état de scroll, '
              'diagnostics de débordement) pour un ou plusieurs identifiants de composants.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'ids': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
                'description':
                    'Liste des identifiants de composants à mesurer. Si omis, mesure les composants racines ou le scope actif.',
              },
              'zoneId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant optionnel de zone (ex: center, west, header) à cibler.',
              },
              'includeScroll': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Inclut les métriques du Scrollable englobant ou interne (true par défaut).',
              },
              'includeZones': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Inclut aussi les entrées de zones montées pour les conteneurs demandés (true par défaut).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'get_runtime_tree',
          description:
              'Retourne la hiérarchie effectivement montée sur la page active ou depuis un rootId, '
              'avec le type de chaque nœud, ses zones/placements, son statut monté et ses dimensions.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'rootId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant racine optionnel. Par défaut, utilise la page active ou le scope courant.',
              },
              'maxDepth': <String, Object?>{
                'type': 'integer',
                'description':
                    'Profondeur maximale de parcours (entre 1 et 12, défaut 6).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'query_repository_data',
          description:
              'Interroge le JsonRepositoryStore actif en lecture seule : liste des repositories, '
              'présence et contenu de leur jsonSchema, échantillons paginés à un chemin JSON et sélections actives Maître/Détail.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'repositoryId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant du repository à inspecter. Si omis, retourne le catalogue résumé.',
              },
              'path': <String, Object?>{
                'type': 'string',
                'description':
                    'Chemin d’attribut JSON optionnel (ex: clients ou clients[0].commandes).',
              },
              'offset': <String, Object?>{
                'type': 'integer',
                'description': 'Indice de départ pour les tableaux (défaut 0).',
              },
              'limit': <String, Object?>{
                'type': 'integer',
                'description':
                    'Nombre maximal d’éléments retournés pour un tableau (entre 1 et 50, défaut 10).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'manage_repository_json_schema',
          description:
              'Lit, infère, valide, associe (create), modifie (update) ou dissocie (delete) le JSON Schema '
              'standard (Draft 7 / Draft 2020-12) d’un repository existant. Participe à la transaction du tour '
              '(rollback et Undo/Redo).',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'required': <String>['action', 'repositoryId'],
            'properties': <String, Object?>{
              'action': <String, Object?>{
                'type': 'string',
                'enum': <String>[
                  'get',
                  'create',
                  'update',
                  'delete',
                  'validate',
                  'infer',
                ],
                'description':
                    'Opération : "get" (lire), "infer" (générer un schéma initial depuis les données), '
                    '"validate" (tester le document contre un schéma), "create" (associer un nouveau schéma), '
                    '"update" (remplacer le schéma existant), "delete" (dissocier le schéma).',
              },
              'repositoryId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant technique ou nom exact d’un repository existant dans le store.',
              },
              'schema': <String, Object?>{
                'type': 'object',
                'description':
                    'Objet JSON Schema standard (requis pour "create" et "update", optionnel pour "validate").',
              },
              'validateCurrentDocument': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Valide immédiatement le document courant avant d’enregistrer le schéma (défaut true). '
                    'Passer false uniquement si tu mets aussi à jour les données du repository dans le même tour.',
              },
              'markPresentKeysRequired': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Utilisé avec "infer" : marque les clés présentes dans le document comme "required" (défaut false).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'capture_element_screenshot',
          description:
              'Capture une copie d’écran PNG isolée d’UN élément précis (composant, carte, zone ou ligne '
              'de liste) sans capturer toute la page ni les contours d’édition. Préfère systématiquement '
              'cet outil à capture_screenshot pour inspecter visuellement un composant individuel.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'componentId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant du composant monté à capturer. Si omis, cible le scope actif ou le composant sélectionné.',
              },
              'zoneId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant optionnel d’une zone précise du conteneur (ex: west, center, header).',
              },
              'occurrenceIndex': <String, Object?>{
                'type': 'integer',
                'description':
                    'Indice 0-based de l’occurrence à capturer dans une liste/table répétée (défaut 0).',
              },
              'scrollIntoView': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Fait défiler automatiquement le conteneur scrollable jusqu’à l’élément avant capture (true par défaut).',
              },
              'contextPadding': <String, Object?>{
                'type': 'number',
                'description':
                    'Marge visuelle autour de l’élément en dp : 0 (défaut) capture uniquement le RepaintBoundary isolé de l’élément ; > 0 inclut ses voisins immédiats.',
              },
              'maxDimension': <String, Object?>{
                'type': 'integer',
                'description':
                    'Dimension maximale en pixels de l’image générée (entre 256 et 1600, défaut 800).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'capture_screenshot',
          description:
              'Capture une image PNG de la page/fenêtre entière de l’application (utilise plutôt '
              'capture_element_screenshot lorsque tu ne veux inspecter qu’un composant ou une zone).',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'componentId': <String, Object?>{
                'type': 'string',
                'description':
                    'Optionnel : si fourni, délègue à capture_element_screenshot ; si omis, capture toute la page.',
              },
              'zoneId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant optionnel de zone lorsque componentId est fourni.',
              },
              'maxDimension': <String, Object?>{
                'type': 'integer',
                'description':
                    'Dimension maximale en pixels de l’image générée (entre 256 et 1600, défaut 1024).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'get_debug_entries',
          description:
              'Lit les journaux et erreurs typés capturés à l’exécution dans debugEntries '
              '(catégories : binding, javascript, font, userInput, rendering, system ; '
              'sévérités : critical, error, warning, info), y compris les erreurs affichées en rouge dans l’IHM.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'type': <String, Object?>{
                'type': 'string',
                'enum': <String>['error', 'log', 'all'],
                'description':
                    'Filtre par nature ("error" par défaut, "log" ou "all").',
              },
              'minSeverity': <String, Object?>{
                'type': 'string',
                'enum': <String>['info', 'warning', 'error', 'critical'],
                'description':
                    'Niveau minimal d’importance à retourner (critical > error > warning > info).',
              },
              'category': <String, Object?>{
                'type': 'string',
                'enum': <String>[
                  'all',
                  'binding',
                  'javascript',
                  'font',
                  'userInput',
                  'rendering',
                  'system',
                ],
                'description':
                    'Filtre par catégorie fonctionnelle : binding, javascript, font, userInput, rendering, system ou all.',
              },
              'componentId': <String, Object?>{
                'type': 'string',
                'description':
                    'Filtre exact sur l’identifiant du composant UI concerné.',
              },
              'visibleInUiOnly': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Ne retourne que les erreurs affichées en rouge dans l’IHM (false par défaut).',
              },
              'query': <String, Object?>{
                'type': 'string',
                'description':
                    'Sous-chaîne optionnelle à rechercher (ex: overflowed, RenderFlex, ID de composant, police).',
              },
              'sinceTurnStart': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Ne retourne que les entrées survenues depuis le début de ce tour IA (false par défaut).',
              },
              'includeStackTrace': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Inclut un extrait condensé de la pile d’appels (true par défaut).',
              },
              'limit': <String, Object?>{
                'type': 'integer',
                'description':
                    'Nombre maximal d’entrées récentes retournées (1 à 50, défaut 20).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'get_datasources_and_providers',
          description:
              'Liste les Datasources CRUD et les DataProviders HTTP/code enregistrés hors d’Appearance '
              '(identifiants, opérations, cibles/filtres, pagination et statut d’exécution/erreurs).',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'datasourceId': <String, Object?>{
                'type': 'string',
                'description': 'Filtre optionnel sur un identifiant de datasource.',
              },
              'providerId': <String, Object?>{
                'type': 'string',
                'description': 'Filtre optionnel sur un identifiant de provider.',
              },
              'includeProblems': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Inclut les diagnostics de cohérence des datasources (true par défaut).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'inspect_bindings_and_diagnostics',
          description:
              'Audite la santé des liaisons JSON sur l’écran (repositories manquants, oubli du préfixe '
              '<repoId>: hors liste en Maître/Détail, jokers [?] sans sélection, clés absentes), '
              'la conformité des données aux JSON Schemas, la cohérence masque/date/données, '
              'les erreurs actives de repository, les composants orphelins et les états forcés.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'componentIds': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
                'description':
                    'Sous-ensemble optionnel d’IDs à auditer (par défaut audite tout l’écran ou le scope).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'get_theme_and_contrast',
          description:
              'Résout tous les rôles Material 3 theme:* en couleurs #RRGGBB effectives et vérifie les '
              'ratios de contraste WCAG AA texte/fond des composants de l’écran.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'componentIds': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
                'description': 'Liste optionnelle d’IDs à vérifier.',
              },
              'onlyIssues': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Si true, ne retourne dans contrastChecks que les composants en échec WCAG AA.',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'get_registry_and_selection',
          description:
              'Retourne les composants et extensions réellement enregistrés dans Registry (ex: Chart ou '
              'composants métier hôtes), les polices disponibles et la sélection active dans l’éditeur.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'includeComponents': <String, Object?>{
                'type': 'boolean',
                'description': 'Inclut la liste des builders du Registry (true par défaut).',
              },
              'includeFonts': <String, Object?>{
                'type': 'boolean',
                'description': 'Inclut les familles de polices disponibles (true par défaut).',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'preview_navigation_or_selection',
          description:
              'Action d’aperçu non destructive (annulée en cas de rollback) : navigue vers une page du '
              'catalogue ou sélectionne une ligne d’un tableau JSON pour alimenter et inspecter une vue Détail.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'pageId': <String, Object?>{
                'type': 'string',
                'description': 'Identifiant d’une page de pageCatalog à afficher.',
              },
              'routePath': <String, Object?>{
                'type': 'string',
                'description': 'Chemin de route débutant par "/" à afficher.',
              },
              'repositoryId': <String, Object?>{
                'type': 'string',
                'description': 'Repository contenant le tableau dont la sélection doit changer.',
              },
              'arrayTemplate': <String, Object?>{
                'type': 'string',
                'description': 'Chemin modèle du tableau (ex: clients ou clients[?].commandes).',
              },
              'index': <String, Object?>{
                'type': 'integer',
                'description': 'Indice 0-based de la ligne à sélectionner (défaut 0).',
              },
              'parentIndices': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'integer'},
                'description': 'Indices parents éventuels pour un sous-tableau imbriqué.',
              },
              'clearSelection': <String, Object?>{
                'type': 'boolean',
                'description': 'Si true, efface la sélection du tableau.',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'select_editor_element',
          description:
              'Sélectionne et met en évidence à distance un élément monté sur le canevas du mode édition '
              '(active le mode édition si nécessaire, fait défiler jusqu’à l’élément, met à jour le chemin '
              'de la bannière et déclenche un halo visuel). Utile pour montrer ou cibler un composant précis.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'componentId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant du composant à sélectionner (requis sauf si clear=true).',
              },
              'zoneId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant optionnel d’une zone du conteneur (ex: west, center, header).',
              },
              'occurrenceIndex': <String, Object?>{
                'type': 'integer',
                'description':
                    'Indice 0-based de l’occurrence à sélectionner dans une liste/table (défaut 0).',
              },
              'enableEditMode': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Active automatiquement le mode édition s’il est désactivé (true par défaut).',
              },
              'scrollIntoView': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Fait défiler jusqu’à l’élément avant sélection (true par défaut).',
              },
              'pulseHighlight': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Déclenche un halo visuel temporaire sur l’élément (true par défaut).',
              },
              'setChatScope': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Si true, restreint aussi le scope actif du chat Vibe à cet élément (false par défaut).',
              },
              'clear': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Si true, efface toute sélection active sur le canevas.',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'register_design_system',
          description:
              'Génère, valide et enregistre un nouveau système de design DESIGN.md dans la liste des choix '
              'possibles du catalogue (et le sélectionne par défaut comme système actif du chat). '
              'À appeler lorsqu’on te demande de créer, extraire ou ajouter un DESIGN.md / Design System '
              'à partir de pièces jointes du chat (captures d’écran, maquettes, fichiers CSS/HTML, SVG, chartes) '
              'ou d’une description. Essaie toujours de récupérer ou reconstruire le logo de la marque depuis les '
              'pièces jointes (URL exacte, Data URI, <svg> inline joint ou extrait du HTML, ou SVG vectoriel minimal '
              'fidèle au logo visible) via le paramètre "logo" et documente-le dans le DESIGN.md.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'required': <String>['name', 'markdown'],
            'properties': <String, Object?>{
              'name': <String, Object?>{
                'type': 'string',
                'description':
                    'Nom lisible du Design System (ex: "Acme Dashboard", "Aurora Dark").',
              },
              'markdown': <String, Object?>{
                'type': 'string',
                'description':
                    'Contenu complet du document DESIGN.md en français (avec les 9 sections : '
                    '1. Visual Theme & Atmosphere, 2. Color Palette & Roles (+ Brand Logo / SVG ou URL si récupéré), '
                    '3. Typography Rules, 4. Component Stylings, 5. Layout Principles, 6. Depth & Elevation, '
                    '7. Do\'s and Don\'ts, 8. Responsive & Desktop Ergonomics, 9. Agent Prompt Guide incluant le logo si disponible).',
              },
              'slug': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant kebab-case optionnel (ex: "acme-dashboard").',
              },
              'category': <String, Object?>{
                'type': 'string',
                'enum': <String>[
                  'productivity-saas',
                  'developer-tools',
                  'ai-platforms',
                  'fintech',
                  'design-creative',
                  'media-retail',
                  'special-retro',
                  'custom',
                ],
                'description':
                    'Catégorie fonctionnelle ou esthétique du système de design (défaut "custom").',
              },
              'tagline': <String, Object?>{
                'type': 'string',
                'description':
                    'Accroche courte résumant la personnalité visuelle sur la carte d’aperçu.',
              },
              'description': <String, Object?>{
                'type': 'string',
                'description':
                    'Description synthétique de l’atmosphère, de la hiérarchie et des usages.',
              },
              'mode': <String, Object?>{
                'type': 'string',
                'enum': <String>['light', 'dark'],
                'description':
                    'Mode lumineux principal ("light" ou "dark") extrait des pièces jointes.',
              },
              'accent': <String, Object?>{
                'type': 'string',
                'description':
                    'Couleur d’accentuation principale au format #RRGGBB.',
              },
              'canvasColor': <String, Object?>{
                'type': 'string',
                'description':
                    'Couleur d’arrière-plan globale (canvas) au format #RRGGBB.',
              },
              'surfaceColor': <String, Object?>{
                'type': 'string',
                'description':
                    'Couleur des cartes et panneaux (surface) au format #RRGGBB.',
              },
              'textColor': <String, Object?>{
                'type': 'string',
                'description': 'Couleur du texte principal au format #RRGGBB.',
              },
              'mutedTextColor': <String, Object?>{
                'type': 'string',
                'description':
                    'Couleur du texte secondaire/atténué au format #RRGGBB.',
              },
              'borderColor': <String, Object?>{
                'type': 'string',
                'description':
                    'Couleur des bordures fines et séparateurs au format #RRGGBB.',
              },
              'cardRadius': <String, Object?>{
                'type': 'number',
                'description':
                    'Rayon d’arrondi représentatif des cartes en dp (ex: 8, 12, 16).',
              },
              'surfaceSystem': <String, Object?>{
                'type': 'string',
                'enum': <String>['material', 'neumorphism', 'liquidGlass'],
                'description': 'Système de rendu de surface (défaut "material").',
              },
              'fontFamily': <String, Object?>{
                'type': 'string',
                'description':
                    'Famille typographique principale recommandée (ex: "Inter").',
              },
              'logo': <String, Object?>{
                'type': 'string',
                'description':
                    'Logo de la marque récupéré depuis les pièces jointes si disponible '
                    '(code <svg...>...</svg> inline compact, Data URI data:image/..., ou URL exacte https://... '
                    'extraite des pièces jointes — ne jamais inventer d’URL externe).',
              },
              'tags': <String, Object?>{
                'type': 'array',
                'items': <String, Object?>{'type': 'string'},
                'description':
                    'Mots-clés facilitant la recherche dans le catalogue.',
              },
              'select': <String, Object?>{
                'type': 'boolean',
                'description':
                    'Si true (défaut), active immédiatement ce Design System dans le chat Vibe ; '
                    'si false, l’ajoute uniquement à la liste des choix possibles.',
              },
            },
          },
        ),
        VibeToolDeclaration(
          name: 'audit_active_page',
          description:
              'Exécute un audit déterministe complet sur la page active (ou le scope actif) : '
              'marges/paddings coupés, dépassements parent/viewport, textes tronqués, erreurs runtime, '
              'attributs calculés @calculs manquants ou non déclarés et contrastes WCAG AA.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
      ];

  /// Construit un registre avec les 5 déclarations standard liées aux [handlers] fournis.
  factory VibeAppToolRegistry.fromStandardHandlers(
    Map<String, VibeToolHandler> handlers,
  ) => VibeAppToolRegistry(<VibeRegisteredTool>[
    for (final declaration in standardDeclarations)
      if (handlers[declaration.name] case final handler?)
        VibeRegisteredTool(declaration: declaration, handler: handler),
  ]);

  final Map<String, VibeRegisteredTool> _tools = <String, VibeRegisteredTool>{};

  /// Déclarations ordonnées de tous les outils disponibles.
  List<VibeToolDeclaration> get declarations => List<VibeToolDeclaration>.unmodifiable([
    for (final tool in _tools.values) tool.declaration,
  ]);

  /// Indique si au moins un outil est enregistré.
  bool get isNotEmpty => _tools.isNotEmpty;

  /// Indique si aucun outil n'est enregistré.
  bool get isEmpty => _tools.isEmpty;

  /// Retourne la déclaration associée à [name], ou `null`.
  VibeToolDeclaration? declarationFor(String name) =>
      _tools[name]?.declaration;

  /// Sérialise les outils au format `tools` attendu par l'API Gemini `v1beta`.
  List<Map<String, Object?>> toGeminiToolsPayload() {
    if (_tools.isEmpty) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      <String, Object?>{
        'functionDeclarations': [
          for (final tool in _tools.values)
            tool.declaration.toGeminiFunctionDeclaration(),
        ],
      },
    ];
  }

  /// Génère la documentation complète et la matrice de décision pour les outils [declarations].
  static String formatDeclarationsGuide(
    List<VibeToolDeclaration> declarations,
  ) {
    if (declarations.isEmpty) return '';
    final buffer = StringBuffer(
      'OUTILS D’INTROSPECTION DE L’APPLICATION EN DIRECT :\n'
      'Règles de décision :\n'
      '- APPELLE OBLIGATOIREMENT un ou plusieurs outils (via Function Calling natif ou '
      '{"message":"inspection en cours","toolCalls":[{"id":"...","name":"...","arguments":{...}}],"vibe":null}) '
      'lorsque : (1) l’utilisateur demande les dimensions/positions/contraintes réelles à l’écran (`get_component_geometry`), '
      '(2) l’utilisateur signale un débordement, une erreur Flutter/RenderFlex, une erreur rouge dans l’IHM (binding, JavaScript, police indisponible, saisie), un texte coupé ou un composant vide/invisible '
      '(`get_debug_entries`, `inspect_bindings_and_diagnostics`, `get_component_geometry`), '
      '(3) tu dois câbler ou diagnostiquer une API / recherche / CRUD (`get_datasources_and_providers`), '
      '(4) tu dois vérifier des couleurs/contrastes (`get_theme_and_contrast`), connaître les extensions/polices ou la sélection (`get_registry_and_selection`), '
      '(5) un tableau de repository est tronqué ("truncatedArrays" -> `query_repository_data`) ou une vue Détail/page secondaire doit être prévisualisée (`preview_navigation_or_selection`), '
      '(6) l’utilisateur demande où se trouve un élément ou de le sélectionner/pointer dans l’éditeur (`select_editor_element`), '
      '(7) l’utilisateur demande de consulter, inférer, valider, associer, modifier ou supprimer le JSON Schema d’un repository existant (`manage_repository_json_schema`), '
      '(8) l’utilisateur demande de générer, extraire ou ajouter un DESIGN.md / Design System dans la liste des choix possibles à partir de pièces jointes ou d’instructions (`register_design_system` — essaie toujours de récupérer aussi le logo via `logo` et de l’inclure dans le DESIGN.md), '
      '(9) une vérification visuelle est utile : préfère `capture_element_screenshot` pour un composant/zone/ligne isolé (plus net et léger) et `capture_screenshot` uniquement pour la page entière.\n'
      '- N’APPELLE PAS d’outil pour les créations ou retouches déclaratives simples dont le JSON courant contient déjà toute l’information.\n'
      '- Regroupe autant que possible tes appels d’outils en un seul lot (par exemple tous les ids utiles dans un seul `get_component_geometry`) afin de limiter le nombre de tours.\n'
      '- Auto-vérification post-rendu : ajoute "verifyRender": true à ta réponse contenant "vibe" si tu souhaites inspecter la géométrie ou une capture d’écran une fois le patch appliqué en aperçu.\n\n'
      'Catalogue des outils disponibles :\n',
    );
    for (final declaration in declarations) {
      buffer.writeln(
        '- ${declaration.name} : ${declaration.description} '
        'Paramètres: ${jsonEncode(declaration.parametersSchema)}',
      );
    }
    return buffer.toString().trimRight();
  }

  static String? _cachedStandardToolsGuide;

  /// Guide statique standard des outils d’introspection pour la mise en cache du prompt.
  static String standardToolsGuide() =>
      _cachedStandardToolsGuide ??= formatDeclarationsGuide(
        standardDeclarations,
      );

  /// Génère une description concise des outils utilisable en mode JSON `"toolCalls"`.
  String formatToolsGuideSection() => formatDeclarationsGuide(declarations);

  /// Exécute un appel d'outil unique en capturant toute erreur sous forme de [VibeToolResult.error].
  Future<VibeToolResult> execute(VibeToolCall call) async {
    final tool = _tools[call.name];
    if (tool == null) {
      return VibeToolResult.error(
        callId: call.id,
        name: call.name,
        message: 'Outil inconnu : "${call.name}".',
      );
    }
    try {
      return await tool.handler(call);
    } catch (error) {
      return VibeToolResult.error(
        callId: call.id,
        name: call.name,
        message: 'Erreur lors de l’exécution de ${call.name} : $error',
      );
    }
  }

  /// Exécute un lot d'appels d'outils (séquentiellement afin de garantir la stabilité des frames UI).
  Future<List<VibeToolResult>> executeAll(List<VibeToolCall> calls) async {
    final results = <VibeToolResult>[];
    for (final call in calls) {
      results.add(await execute(call));
    }
    return List<VibeToolResult>.unmodifiable(results);
  }
}
