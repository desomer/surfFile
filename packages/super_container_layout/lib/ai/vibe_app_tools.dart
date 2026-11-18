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
      case 'capture_screenshot':
        final target = data['target'] ?? 'viewport';
        final w = data['logicalWidth'];
        final h = data['logicalHeight'];
        if (w != null && h != null) {
          return '$target (${_fmtNum(w)}×${_fmtNum(h)} dp)';
        }
        return '$target';
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
              'schémas, échantillons paginés à un chemin JSON et sélections actives Maître/Détail.',
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
          name: 'capture_screenshot',
          description:
              'Capture une image PNG réelle de la vue applicative ou d’un composant monté précis '
              'pour vérifier visuellement le rendu, l’alignement ou les chevauchements.',
          parametersSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'componentId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant du composant à capturer. Si omis, capture la vue entière de l’application.',
              },
              'zoneId': <String, Object?>{
                'type': 'string',
                'description':
                    'Identifiant optionnel de zone du composant à capturer.',
              },
              'maxDimension': <String, Object?>{
                'type': 'integer',
                'description':
                    'Dimension maximale en pixels de l’image générée (entre 256 et 1600, défaut 1024).',
              },
            },
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
      'OUTILS D’INTROSPECTION DE L’APPLICATION EN DIRECT (LECTURE SEULE) :\n'
      'Règles de décision :\n'
      '- APPELLE OBLIGATOIREMENT un ou plusieurs outils (via Function Calling natif ou '
      '{"message":"inspection en cours","toolCalls":[{"id":"...","name":"...","arguments":{...}}],"vibe":null}) '
      'lorsque : (1) l’utilisateur demande les dimensions/positions/contraintes réelles à l’écran, '
      '(2) l’utilisateur signale un débordement, un texte coupé, un chevauchement ou un espace vide, '
      '(3) tu dois adapter un composant à la taille réelle de la fenêtre/zone parente ou inspecter un slot monté absent du JSON, '
      '(4) un tableau de repository est tronqué ("truncatedArrays") et tu as besoin des éléments complets, ou '
      '(5) une vérification visuelle ("capture_screenshot") est demandée ou utile.\n'
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

  /// Guide statique standard des 5 outils d’introspection pour la mise en cache du prompt.
  static String standardToolsGuide() =>
      formatDeclarationsGuide(standardDeclarations);

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
