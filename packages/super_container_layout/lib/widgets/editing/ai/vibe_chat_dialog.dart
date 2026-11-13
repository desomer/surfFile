/// Interface de chat IA (« Vibe ») pour la génération et la modification incrémentale d'écrans ([VibeChatDialog]).
///
/// Met en cache le guide `SCREEN_JSON_AI_GUIDE.md` ([VibeChatDialog.warmUp]), assemble un instantané
/// JSON compact (global ou ciblé sur un [VibeChatScope]), diffuse la réponse en direct via
/// [streamGemini] ([VibeAiSpeedMode]) ou [callGemini], propose au besoin un questionnaire
/// de clarification interactif ([VibeAskUserRequest]), et applique le patch via `AppearanceTransfer.applyVibe`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_ui/material_ui.dart';

import '../../../ai/call_gemini.dart';
import '../../../ai/vibe_ask_user.dart';
import '../../../ai/vibe_stream_parser.dart';
import '../../../models/component_config.dart';
import '../../../models/json_numbers.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_store.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog.dart';
import '../slots/editor_context_menu.dart';

export '../../../ai/call_gemini.dart' show GeminiStreamEvent, VibeAiSpeedMode;
export '../../../ai/vibe_ask_user.dart'
    show
        VibeAskUserFieldType,
        VibeAskUserQuestion,
        VibeAskUserRequest,
        VibeQuestioningLevel;
export '../../../ai/vibe_chat_attachment.dart';
export '../../../ai/vibe_stream_parser.dart' show VibeStreamSnapshot;
export '../slots/editor_context_menu.dart' show VibeChatScope;

/// Panneau et boîte de dialogue de chat avec l'IA Vibe pour créer ou modifier l'interface en langage naturel.
class VibeChatDialog extends StatefulWidget {
  /// Crée un panneau de chat Vibe IA connecté à [controller] et [codec].
  const VibeChatDialog({
    required this.controller,
    required this.codec,
    required this.onClose,
    required this.onDrag,
    required this.generate,
    this.streamGenerate,
    this.initialSpeedMode = VibeAiSpeedMode.fast,
    this.initialQuestioningLevel = VibeQuestioningLevel.balanced,
    this.onQuestioningLevelChanged,
    this.scope,
    this.onScopeChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.validateAppearance,
    this.registry,
    super.key,
  });

  /// Active la journalisation multi-blocs détaillée des prompts, réponses brutes et patches JSON.
  ///
  /// Désactivé par défaut afin d'éviter le blocage de l'isolate UI sur les charges JSON volumineuses.
  static bool verboseLogging = false;

  /// Instructions système invariantes transmises au modèle GenUI pour le chat Vibe IA.
  static const String defaultSystemInstruction = '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide de modélisation et l’état actuel de l’application fournis.
Renvoie uniquement un objet JSON en plaçant impérativement la clé "message" EN PREMIER (avant "askUser" et "vibe") pour permettre l'affichage instantané en streaming, selon l'un des 3 modes suivants :
1. Création ou modification directe de l'écran : renvoie {"message":"résumé bref en français","vibe":{...}}. Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "behaviors", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
2. Question pure ou demande d'information sans modification de l'écran : renvoie {"message":"réponse claire en français","vibe":null} (ou omets le champ "vibe") sans modifier l'écran.
3. Clarification interactive ("askUser") selon le NIVEAU DE QUESTIONNEMENT indiqué dans le contexte du tour : renvoie {"message":"courte introduction en français","askUser":{"questions":[{"id":"...","title":"...","type":"single|multi|boolean|text","options":["..."],"default":...}]},"vibe":null}.
Règles pour "askUser" :
- Respecte strictement le NIVEAU DE QUESTIONNEMENT du tour courant (si le niveau vaut 0/Aucun ou si les réponses viennent d'être fournies, n'utilise jamais "askUser" et génère directement {"message":"...","vibe":{...}}).
- Fournis toujours des valeurs "default" pertinentes sur chaque question posée.
Réutilise les identifiants des conteneurs de l'état actuel, y compris ceux dont la configuration est encore celle par défaut. Les identifiants du guide (comme "contA") sont des exemples, pas des racines d'écran implicites.
Tout nouveau composant doit être rattaché par les placements à un conteneur existant ou à une page déclarée dans pageCatalog. Créer un layout isolé ne l'affiche pas.
Si une opération crée une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Si la conversation mentionne une erreur sur une réponse précédente, identifie la cause indiquée et corrige-la sans reproduire la même erreur.
Ne renvoie aucun Markdown ni texte hors du JSON. Si une information mineure manque sans justifier un questionnaire, fais une hypothèse raisonnable et indique-la dans "message".''';

  static const List<String> _guideAssets = [
    'SCREEN_JSON_AI_GUIDE.md',
    'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
  ];

  static String? _cachedRootBundleGuide;
  static Future<String>? _inFlightRootBundleGuide;

  /// Contrôleur réactif de l'apparence courante à lire et mettre à jour.
  final ValueNotifier<Appearance> controller;

  /// Codec de sérialisation GenUI utilisé pour exporter l'état et appliquer le patch.
  final AppearanceCodec codec;

  /// Callback déclenché à la fermeture du panneau de chat.
  final VoidCallback onClose;

  /// Callback déclenché lors du déplacement de l'en-tête du panneau.
  final ValueChanged<Offset> onDrag;

  /// Générateur asynchrone complet (rétrocompatible avec les appelants et tests existants).
  final Future<String> Function(String prompt) generate;

  /// Générateur optionnel en flux SSE incrémental ([GeminiStreamEvent]).
  final Stream<GeminiStreamEvent> Function(
    String prompt, {
    String? systemInstruction,
    String? staticGuide,
    List<VibeChatAttachment> attachments,
    VibeAiSpeedMode speedMode,
  })?
  streamGenerate;

  /// Mode de vitesse initial sélectionné à l'ouverture du panneau ([VibeAiSpeedMode.fast] par défaut).
  final VibeAiSpeedMode initialSpeedMode;

  /// Niveau initial de questionnement préalable ([VibeQuestioningLevel.balanced] par défaut).
  final VibeQuestioningLevel initialQuestioningLevel;

  /// Callback optionnel notifié lorsque l'utilisateur ajuste le niveau de questionnement via le slider.
  final ValueChanged<VibeQuestioningLevel>? onQuestioningLevelChanged;

  /// Périmètre restreint optionnel limitant les modifications de l'IA à un sous-arbre.
  final VibeChatScope? scope;

  /// Callback notifié lorsque l'utilisateur efface ou modifie la restriction de [scope].
  final ValueChanged<VibeChatScope?>? onScopeChanged;

  /// Sélecteur personnalisé optionnel de pièces jointes (fichiers images ou texte).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur personnalisé optionnel du presse-papiers pour les pièces jointes.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Validation supplémentaire optionnelle de l'[Appearance] générée (ex. routes de pages).
  final void Function(Appearance appearance)? validateAppearance;

  /// Registre optionnel fournissant les composants instanciés et leurs configurations par défaut.
  final Registry? registry;

  static Future<String> _loadGuideFromBundle(AssetBundle bundle) async {
    final isRoot = identical(bundle, rootBundle);
    if (isRoot) {
      final cached = _cachedRootBundleGuide;
      if (cached != null) return cached;
      final inFlight = _inFlightRootBundleGuide;
      if (inFlight != null) return inFlight;
    }

    Future<String> load() async {
      FlutterError? lastError;
      for (final asset in _guideAssets) {
        try {
          final guide = await bundle.loadString(asset);
          if (guide.trim().isNotEmpty) {
            if (isRoot) {
              _cachedRootBundleGuide = guide;
            }
            return guide;
          }
          lastError = FlutterError('Asset "$asset" is empty.');
        } on FlutterError catch (error) {
          lastError = error;
        }
      }
      throw FlutterError(
        'Unable to load the Vibe screen guide from '
        '${_guideAssets.map((asset) => '"$asset"').join(' or ')}.'
        '${lastError == null ? '' : ' $lastError'}',
      );
    }

    if (!isRoot) {
      return load();
    }
    final future = load();
    _inFlightRootBundleGuide = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRootBundleGuide, future)) {
        _inFlightRootBundleGuide = null;
      }
    }
  }

  /// Précharge en mémoire le guide `SCREEN_JSON_AI_GUIDE.md` depuis [bundle] et préchauffe
  /// silencieusement la connexion TLS ainsi que le cache de contexte Gemini pour [speedMode].
  static Future<void> warmUp(
    AssetBundle bundle, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
  }) async {
    try {
      final isWidgetTestBinding = WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
      final hasDotenvKey =
          dotenv.isInitialized &&
          (dotenv.env['GEMINI_API_KEY'] ?? '').trim().isNotEmpty;
      if (isWidgetTestBinding &&
          !hasDotenvKey &&
          identical(bundle, rootBundle)) {
        return;
      }
      final guide = await _loadGuideFromBundle(bundle);
      if (isWidgetTestBinding && !hasDotenvKey) {
        return;
      }
      await warmUpGemini(
        systemInstruction: defaultSystemInstruction,
        staticGuide: guide,
        speedMode: speedMode,
      );
    } catch (_) {
      // Le préchauffage est purement opportuniste et ne lève jamais d'exception.
    }
  }

  /// Opens the Vibe AI chat targeted at [scope]: reuses the active
  /// `StyleEditBanner` panel when mounted, or falls back to an editor dialog.
  static Future<void> showScoped(
    BuildContext context,
    VibeChatScope scope,
  ) async {
    if (VibeChatScope.onOpenRequested case final handler? when handler(scope)) {
      return;
    }
    final appearance = AppearanceScope.controllerOf(context);
    if (appearance == null) return;
    final codec = AppearanceServicesScope.codecOf(context);
    final registry = SuperApp.maybeOf(context)?.registry;
    await showEditorDialog<void>(
      context: context,
      target: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 440,
          height: 600,
          child: VibeChatDialog(
            controller: appearance,
            codec: codec,
            registry: registry,
            scope: scope,
            onClose: () => Navigator.of(dialogContext).pop(),
            onDrag: (_) {},
            generate: callGemini,
          ),
        ),
      ),
    );
  }

  /// Returns the direct child slot IDs placed inside [component], optionally
  /// restricted to [onlyZoneId].
  static Iterable<String> _childrenOfComponent(
    ComponentConfig? component, {
    String? onlyZoneId,
  }) {
    if (component == null) return const [];
    if (onlyZoneId != null && onlyZoneId.isNotEmpty) {
      return switch (component) {
        final SuperLayoutConfig layout => () {
          final zone = SuperLayoutZone.values
              .where((z) => z.name == onlyZoneId)
              .firstOrNull;
          return zone == null
              ? const <String>[]
              : layout.placementsOf(layout.contentZone(zone));
        }(),
        final SuperListViewConfig list => () {
          final zone = SuperLayoutZone.values
              .where((z) => z.name == onlyZoneId)
              .firstOrNull;
          return zone == null
              ? const <String>[]
              : list.template.placementsOf(list.template.contentZone(zone));
        }(),
        final SuperTabConfig tab => tab.slotsOf(onlyZoneId),
        final SuperConditionalConfig cond => cond.slotsOf(onlyZoneId),
        final SuperTreeViewConfig tree => tree.slotsOf(onlyZoneId),
        final SuperTableConfig table => table.slotsOf(onlyZoneId),
        final NativeComponentConfig native => native.slotsOf(onlyZoneId),
        final ScaffoldPageConfig scaffold => scaffold.native.slotsOf(
          onlyZoneId,
        ),
        _ => const <String>[],
      };
    }
    return switch (component) {
      final SuperLayoutConfig layout => layout.placedSlotIds,
      final SuperListViewConfig list => list.template.placedSlotIds,
      final SuperTabConfig tab => tab.placedSlotIds,
      final SuperConditionalConfig cond => cond.placedSlotIds,
      final SuperTreeViewConfig tree => tree.placedSlotIds,
      final SuperTableConfig table => table.placedSlotIds,
      final NativeComponentConfig native => native.placements.values.expand(
        (ids) => ids,
      ),
      final ScaffoldPageConfig scaffold =>
        scaffold.native.placements.values.expand((ids) => ids),
      _ => const <String>[],
    };
  }

  static Iterable<String> _placedIdsInPatchMap(
    Map<Object?, Object?> map, {
    String? onlyZoneId,
  }) sync* {
    Iterable<String> fromPlacementsMap(Object? placements) sync* {
      if (placements is! Map) return;
      for (final entry in placements.entries) {
        if (onlyZoneId != null && entry.key != onlyZoneId) continue;
        final list = entry.value;
        if (list is List) {
          for (final item in list) {
            if (item is String && item.trim().isNotEmpty) {
              yield item.trim();
            } else if (item is Map && item['id'] is String) {
              final id = (item['id'] as String).trim();
              if (id.isNotEmpty) yield id;
            }
          }
        }
      }
    }

    yield* fromPlacementsMap(
      map.containsKey('placements') ? map['placements'] : map['zones'],
    );
    if (map['template'] is Map) {
      final t = map['template'] as Map;
      yield* fromPlacementsMap(
        t.containsKey('placements') ? t['placements'] : t['zones'],
      );
    }
    if (map['row'] is Map) {
      final r = map['row'] as Map;
      yield* fromPlacementsMap(
        r.containsKey('placements') ? r['placements'] : r['zones'],
      );
    }
    if (onlyZoneId == null || onlyZoneId == 'tabs') {
      if (map['tabs'] is List) {
        for (final item in map['tabs'] as List) {
          if (item is String && item.trim().isNotEmpty) yield item.trim();
          if (item is Map && item['id'] is String) {
            final id = (item['id'] as String).trim();
            if (id.isNotEmpty) yield id;
          }
        }
      }
    }
    if (onlyZoneId == null || onlyZoneId == 'content') {
      if (map['content'] is List) {
        for (final item in map['content'] as List) {
          if (item is String && item.trim().isNotEmpty) yield item.trim();
          if (item is Map && item['id'] is String) {
            final id = (item['id'] as String).trim();
            if (id.isNotEmpty) yield id;
          }
        }
      }
    }
    if (map['contents'] is Map) {
      for (final entry in (map['contents'] as Map).entries) {
        final regionKey = 'content:${entry.key}';
        if (onlyZoneId != null &&
            onlyZoneId != regionKey &&
            onlyZoneId != entry.key) {
          continue;
        }
        if (entry.value is List) {
          for (final item in entry.value as List) {
            if (item is String && item.trim().isNotEmpty) yield item.trim();
            if (item is Map && item['id'] is String) {
              final id = (item['id'] as String).trim();
              if (id.isNotEmpty) yield id;
            }
          }
        }
      }
    }
  }

  /// Returns the direct parent component IDs in [current] that place
  /// [scope.canonicalComponentId], plus [scope.canonicalParentComponentId] if
  /// specified.
  static Set<String> parentIdsOfScope(Appearance current, VibeChatScope scope) {
    final targetId = scope.canonicalComponentId;
    final parents = <String>{};
    for (final entry in current.components.entries) {
      if (entry.key == targetId) continue;
      if (_childrenOfComponent(entry.value).contains(targetId)) {
        parents.add(entry.key);
      }
    }
    if (scope.canonicalParentComponentId case final explicitParent?) {
      parents.add(explicitParent);
    }
    return parents;
  }

  /// Root component IDs of the effective modifiable scope: the parent
  /// container(s) of [scope.canonicalComponentId] when present, together with
  /// [scope.canonicalComponentId] itself.
  static Set<String> _scopeRootIds(Appearance current, VibeChatScope scope) {
    final targetId = scope.canonicalComponentId;
    final parents = parentIdsOfScope(current, scope);
    return <String>{...parents, targetId};
  }

  /// Collects all existing component IDs in [current] belonging to [scope]'s
  /// modifiable subtree, extended to the parent container of the selection and
  /// its full subtree.
  static Set<String> _existingSubtreeIds(
    Appearance current,
    VibeChatScope scope,
  ) {
    final visited = <String>{};
    final pending = <String>[..._scopeRootIds(current, scope)];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!visited.add(id)) continue;
      pending.addAll(_childrenOfComponent(current.components[id]));
    }
    return visited;
  }

  /// Filters an incoming GenUI [patch] so that only changes belonging to
  /// [scope] and its parent container's subtree are kept.
  ///
  /// Out-of-scope edits (ancestors above the parent, unrelated branches,
  /// global theme properties, `pageCatalog`) are stripped automatically.
  static Map<String, dynamic> filterPatchToScope(
    Appearance current,
    Map<String, dynamic> patch,
    VibeChatScope scope,
  ) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    final targetId = scope.canonicalComponentId;
    final rawTargetId = scope.componentId;
    final parents = parentIdsOfScope(current, scope);
    final topRootIds = parents.isNotEmpty ? parents : <String>{targetId};

    final existingSubtree = _existingSubtreeIds(current, scope);
    final outsideExistingIds = <String>{
      for (final id in current.components.keys)
        if (!existingSubtree.contains(id) && id != targetId) id,
    };

    final allowedSubtreeIds = <String>{...existingSubtree};
    final rawComponents = payload['components'];
    final placedByOutsideIds = <String>{};

    if (rawComponents is Map) {
      for (final entry in rawComponents.entries) {
        final cid = entry.key;
        final cval = entry.value;
        if (cid is! String || cval is! Map) continue;
        if (outsideExistingIds.contains(cid)) {
          placedByOutsideIds.addAll(_placedIdsInPatchMap(cval));
        }
      }

      final queue = <String>[...allowedSubtreeIds];

      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        for (final childId in _childrenOfComponent(current.components[id])) {
          if (!outsideExistingIds.contains(childId) &&
              allowedSubtreeIds.add(childId)) {
            queue.add(childId);
          }
        }
        if (rawComponents[id] is Map) {
          for (final childId in _placedIdsInPatchMap(
            rawComponents[id] as Map,
          )) {
            if (!outsideExistingIds.contains(childId) &&
                allowedSubtreeIds.add(childId)) {
              queue.add(childId);
            }
          }
        }
      }
    }

    final filteredComponents = <String, Object?>{};
    if (rawComponents is Map) {
      for (final entry in rawComponents.entries) {
        final cid = entry.key;
        final cval = entry.value;
        if (cid is! String) continue;
        if (allowedSubtreeIds.contains(cid)) {
          if (topRootIds.contains(cid) && cval == null) continue;
          filteredComponents[cid] = cval;
        } else if (!current.components.containsKey(cid) &&
            !outsideExistingIds.contains(cid) &&
            !placedByOutsideIds.contains(cid)) {
          // Detached newly created component: keep so validation can report it.
          filteredComponents[cid] = cval;
        }
      }
    }

    bool isStyleAllowed(String styleId) {
      if (allowedSubtreeIds.contains(styleId)) return true;
      if (styleId.endsWith(':item')) {
        final base = styleId.substring(0, styleId.length - 5);
        if (allowedSubtreeIds.contains(base)) return true;
      }
      if (styleId == rawTargetId ||
          styleId == targetId ||
          styleId == '$targetId:item') {
        return true;
      }
      return false;
    }

    final filteredStyles = <String, Object?>{};
    if (payload['styles'] case final Map rawStyles) {
      for (final entry in rawStyles.entries) {
        if (entry.key is String && isStyleAllowed(entry.key as String)) {
          filteredStyles[entry.key as String] = entry.value;
        }
      }
    }

    final filteredBehaviors = <String, Object?>{};
    if (payload['behaviors'] case final Map rawBehaviors) {
      for (final entry in rawBehaviors.entries) {
        final bid = entry.key;
        if (bid is String &&
            (allowedSubtreeIds.contains(bid) || bid == rawTargetId)) {
          filteredBehaviors[bid] = entry.value;
        }
      }
    }

    return <String, dynamic>{
      if (filteredComponents.isNotEmpty) 'components': filteredComponents,
      if (filteredStyles.isNotEmpty) 'styles': filteredStyles,
      if (filteredBehaviors.isNotEmpty) 'behaviors': filteredBehaviors,
    };
  }

  /// Exporte un instantané JSON compact et minifié du sous-arbre de [scope]
  /// (incluant son conteneur parent et ses enfants) depuis [appearance] pour le prompt IA.
  static String exportScopedAi(
    Appearance appearance,
    VibeChatScope scope, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final targetId = scope.canonicalComponentId;
    final rawTargetId = scope.componentId;
    final parentIds = parentIdsOfScope(appearance, scope);
    final subtreeIds = <String>{
      targetId,
      ...parentIds,
      ..._existingSubtreeIds(appearance, scope),
    };
    final compactJson = codec.toCompactJson(appearance);
    final allComponents =
        compactJson['components'] as Map<String, Object?>? ?? const {};
    final allStyles =
        compactJson['styles'] as Map<String, Object?>? ?? const {};
    final allBehaviors =
        compactJson['behaviors'] as Map<String, Object?>? ?? const {};

    final scopedComponents = <String, Object?>{
      for (final id in subtreeIds)
        if (allComponents.containsKey(id)) id: allComponents[id],
    };
    final scopedStyles = <String, Object?>{
      for (final entry in allStyles.entries)
        if (subtreeIds.contains(entry.key) ||
            entry.key == rawTargetId ||
            entry.key == targetId ||
            entry.key == '$targetId:item' ||
            (entry.key.endsWith(':item') &&
                subtreeIds.contains(
                  entry.key.substring(0, entry.key.length - 5),
                )))
          entry.key: entry.value,
    };
    final scopedBehaviors = <String, Object?>{
      for (final entry in allBehaviors.entries)
        if (subtreeIds.contains(entry.key) || entry.key == rawTargetId)
          entry.key: entry.value,
    };

    return jsonEncode(
      JsonNumbers.normalizeMap({
        'scope': {
          'componentId': targetId,
          if (rawTargetId != targetId) 'surfaceId': rawTargetId,
          'zoneId': ?scope.zoneId,
          if (parentIds.isNotEmpty)
            'parentComponentId': parentIds.length == 1
                ? parentIds.first
                : parentIds.toList(),
          'label': scope.displayLabel,
        },
        'components': scopedComponents,
        'styles': scopedStyles,
        if (scopedBehaviors.isNotEmpty) 'behaviors': scopedBehaviors,
      }),
    );
  }

  @override
  State<VibeChatDialog> createState() => _VibeChatDialogState();
}

class _VibeChatDialogState extends State<VibeChatDialog> {
  static const String _initialGreetingText =
      'Décris l’écran à créer ou les changements souhaités.';
  static const int _maxConversationEntries = 8;

  final _input = TextEditingController();
  final _pendingAttachments = <VibeChatAttachment>[];
  final _messages = <_ChatMessage>[
    const _ChatMessage(text: _initialGreetingText, isUser: false),
  ];
  final ValueNotifier<VibeStreamSnapshot?> _streamingSnapshot =
      ValueNotifier<VibeStreamSnapshot?>(null);
  VibeStreamSnapshot? _pendingSnapshot;
  bool _frameSnapshotScheduled = false;
  bool _didWarmUpDependencies = false;
  bool _sending = false;
  String? _lastFailedResponse;
  String? _attachmentError;
  late VibeChatScope? _scope = widget.scope;
  late VibeAiSpeedMode _speedMode = widget.initialSpeedMode;
  late VibeQuestioningLevel _questioningLevel = widget.initialQuestioningLevel;

  bool get _isAfterAskUserReply {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.isUser) {
        return msg.promptText != null;
      }
    }
    return false;
  }

  bool get _usesStreamingGenerator =>
      widget.streamGenerate != null || identical(widget.generate, callGemini);

  Appearance get _currentAppearance =>
      widget.registry?.appearanceSnapshot(widget.controller.value) ??
      widget.controller.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didWarmUpDependencies && _usesStreamingGenerator) {
      _didWarmUpDependencies = true;
      unawaited(
        VibeChatDialog.warmUp(
          DefaultAssetBundle.of(context),
          speedMode: _speedMode,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(VibeChatDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _scope = widget.scope;
    }
    if (oldWidget.initialSpeedMode != widget.initialSpeedMode) {
      _speedMode = widget.initialSpeedMode;
      if (_usesStreamingGenerator) {
        unawaited(
          VibeChatDialog.warmUp(
            DefaultAssetBundle.of(context),
            speedMode: _speedMode,
          ),
        );
      }
    }
    if (oldWidget.initialQuestioningLevel != widget.initialQuestioningLevel) {
      _questioningLevel = widget.initialQuestioningLevel;
    }
  }

  void _setSpeedMode(VibeAiSpeedMode mode) {
    if (_speedMode == mode || _sending) return;
    setState(() => _speedMode = mode);
    if (_usesStreamingGenerator) {
      unawaited(
        VibeChatDialog.warmUp(DefaultAssetBundle.of(context), speedMode: mode),
      );
    }
  }

  void _setQuestioningLevel(VibeQuestioningLevel level) {
    if (_questioningLevel == level || _sending) return;
    setState(() => _questioningLevel = level);
    widget.onQuestioningLevelChanged?.call(level);
  }

  void _publishStreamSnapshot(VibeStreamSnapshot snapshot) {
    if (!_frameSnapshotScheduled) {
      _streamingSnapshot.value = snapshot;
      _frameSnapshotScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _frameSnapshotScheduled = false;
        if (!mounted || !_sending) return;
        final pending = _pendingSnapshot;
        if (pending != null) {
          _pendingSnapshot = null;
          _streamingSnapshot.value = pending;
        }
      });
    } else {
      _pendingSnapshot = snapshot;
    }
  }

  void _clearScope() {
    setState(() => _scope = null);
    widget.onScopeChanged?.call(null);
  }

  @override
  void dispose() {
    _pendingSnapshot = null;
    _streamingSnapshot.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _attachFromPicker() async {
    if (_sending) return;
    setState(() => _attachmentError = null);
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _pendingAttachments.addAll(picked);
        _attachmentError = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _attachmentError = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Lecture impossible : ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Impossible d’importer le fichier : ${_describeErrorCause(error)}',
        );
      }
    }
  }

  Future<void> _attachFromClipboard() async {
    if (_sending) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucun fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() {
        _pendingAttachments.addAll(pasted);
        _attachmentError = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _attachmentError = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Lecture impossible : ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Impossible de coller depuis le presse-papiers : '
              '${_describeErrorCause(error)}',
        );
      }
    }
  }

  void _removePendingAttachment(int index) {
    if (_sending || index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      _pendingAttachments.removeAt(index);
      _attachmentError = null;
    });
  }

  String _describeErrorCause(Object error) {
    if (error is FormatException) {
      final offset = error.offset;
      final source = error.source;
      if (offset != null && source is String && source.isNotEmpty) {
        final start = (offset - 40).clamp(0, source.length);
        final end = (offset + 40).clamp(0, source.length);
        final snippet = source.substring(start, end).replaceAll('\n', ' ');
        return '${error.message} (offset $offset, près de "$snippet")';
      }
      return error.message;
    }
    if (error is ArgumentError) {
      final name = error.name;
      final message = error.message?.toString() ?? error.toString();
      return name != null && name.isNotEmpty ? '$name : $message' : message;
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is FlutterError) {
      return error.message;
    }
    return '$error';
  }

  Future<void> _send() async {
    final request = _input.text.trim();
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    if ((request.isEmpty && attachments.isEmpty) || _sending) return;
    _input.clear();
    setState(() {
      _pendingAttachments.clear();
      _attachmentError = null;
      for (var i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        if (msg.askUser != null &&
            msg.askUserAnswers == null &&
            !msg.askUserDismissed) {
          _messages[i] = msg.copyWith(askUserDismissed: true);
        }
      }
    });
    await _runGenerationTurn(
      displayUserText: request,
      attachments: attachments,
    );
  }

  Future<void> _submitAskUser(
    int messageIndex,
    Map<String, Object?> answers, {
    required bool usedDefaults,
  }) async {
    if (_sending || messageIndex < 0 || messageIndex >= _messages.length) {
      return;
    }
    final target = _messages[messageIndex];
    final request = target.askUser;
    if (request == null ||
        target.askUserAnswers != null ||
        target.askUserDismissed) {
      return;
    }
    final normalizedAnswers = Map<String, Object?>.unmodifiable(answers);
    setState(() {
      _messages[messageIndex] = target.copyWith(
        askUserAnswers: normalizedAnswers,
        askUserUsedDefaults: usedDefaults,
      );
    });
    final summary = request.formatDisplaySummary(
      normalizedAnswers,
      usedDefaults: usedDefaults,
    );
    final displaySummary =
        '${usedDefaults ? 'Valeurs par défaut retenues' : 'Choix validés'} :\n$summary';
    final promptReply = request.formatPromptReply(
      normalizedAnswers,
      usedDefaults: usedDefaults,
    );
    await _runGenerationTurn(
      displayUserText: displaySummary,
      promptOverride: promptReply,
    );
  }

  Future<void> _runGenerationTurn({
    required String displayUserText,
    String? promptOverride,
    List<VibeChatAttachment> attachments = const [],
  }) async {
    _lastFailedResponse = null;
    setState(() {
      _sending = true;
      _messages.add(
        _ChatMessage(
          text: displayUserText,
          promptText: promptOverride,
          isUser: true,
          attachments: attachments,
        ),
      );
    });

    debugPrint(
      '[Vibe IA] Nouvelle demande utilisateur : "$displayUserText" '
      '(pièces jointes: ${attachments.map((a) => a.name).toList()})',
    );
    try {
      final guide = await _loadGuide(context);
      final turnPrompt = _buildTurnPrompt();
      final generated = await _generateAndApply(
        turnPrompt,
        systemGuide: guide,
        attachments: attachments,
      );
      if (generated.appearance case final appearance?) {
        widget.controller.value = appearance;
        debugPrint(
          '[Vibe IA] Apparence mise à jour avec succès '
          '(composants: ${appearance.components.length}, '
          'styles: ${appearance.styles.length}, '
          'pages: ${appearance.pageCatalog.pages.length}).',
        );
      } else if (generated.askUser case final askUser?) {
        debugPrint(
          '[Vibe IA] Questionnaire de clarification reçu '
          '(${askUser.questions.length} question(s)).',
        );
      } else {
        debugPrint(
          '[Vibe IA] Réponse textuelle affichée sans modification d’apparence.',
        );
      }
      final summary = generated.result['message'];
      final fallbackText =
          generated.askUser != null && generated.appearance == null
          ? 'Précise tes préférences :'
          : 'Modifications appliquées.';
      _appendMessage(
        summary is String && summary.trim().isNotEmpty
            ? summary.trim()
            : fallbackText,
        askUser: generated.appearance == null ? generated.askUser : null,
      );
    } on FormatException catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (FormatException): $cause\n'
        'Source: ${error.source ?? "n/a"} (offset: ${error.offset ?? "n/a"})\n'
        '$stackTrace',
      );
      _appendMessage(
        'Réponse Vibe invalide : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on ArgumentError catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (ArgumentError): $cause\n$stackTrace',
      );
      _appendMessage(
        'Modification refusée : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on StateError catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (StateError): $cause\n$stackTrace',
      );
      _appendMessage(
        'Modification impossible : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on FlutterError catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint('AI screen guide could not be loaded: $cause\n$stackTrace');
      _appendMessage(
        'Guide de génération indisponible : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on Exception catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (${error.runtimeType}): $cause\n'
        '$stackTrace',
      );
      _appendMessage(
        'Génération impossible (${error.runtimeType}) : $cause',
        failedResponse: _lastFailedResponse,
      );
    } catch (error, stackTrace) {
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed with unexpected error '
        '(${error.runtimeType}): $cause\n$stackTrace',
      );
      _appendMessage(
        'Génération impossible (${error.runtimeType}) : $cause',
        failedResponse: _lastFailedResponse,
      );
    } finally {
      _pendingSnapshot = null;
      _streamingSnapshot.value = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  void _logLong(String title, String content) {
    if (!VibeChatDialog.verboseLogging) {
      debugPrint('$title (${content.length} caractères).');
      return;
    }
    debugPrint('$title (${content.length} caractères) :');
    const chunkSize = 800;
    if (content.length <= chunkSize) {
      debugPrint(content);
      return;
    }
    for (var start = 0; start < content.length; start += chunkSize) {
      final end = (start + chunkSize < content.length)
          ? start + chunkSize
          : content.length;
      debugPrint(content.substring(start, end));
    }
  }

  Future<String> _invokeGenerate(
    String prompt,
    List<VibeChatAttachment> attachments,
  ) {
    final generator = widget.generate;
    if (generator
        is Future<String> Function(
          String, {
          List<VibeChatAttachment> attachments,
        })) {
      return generator(prompt, attachments: attachments);
    }
    return generator(prompt);
  }

  Future<String> _consumeStreamingGenerate(
    String turnPrompt, {
    required String systemGuide,
    required List<VibeChatAttachment> attachments,
  }) async {
    final streamFn = widget.streamGenerate ?? streamGemini;
    final parser = VibeIncrementalStreamParser();
    _pendingSnapshot = null;
    _streamingSnapshot.value = VibeStreamSnapshot.empty;

    var finalAccumulated = '';
    final stream = streamFn(
      turnPrompt,
      systemInstruction: VibeChatDialog.defaultSystemInstruction,
      staticGuide: systemGuide,
      attachments: attachments,
      speedMode: _speedMode,
    );

    await for (final event in stream) {
      if (event.deltaText.isNotEmpty) {
        final snapshot = parser.addChunk(event.deltaText);
        _publishStreamSnapshot(snapshot);
      } else if (event.isDone &&
          parser.rawBuffer.isEmpty &&
          event.accumulatedText.isNotEmpty) {
        parser.addChunk(event.accumulatedText);
      }
      if (event.accumulatedText.isNotEmpty) {
        finalAccumulated = event.accumulatedText;
      }
      if (event.isDone) {
        _pendingSnapshot = null;
        _streamingSnapshot.value = parser.current;
      }
    }

    return parser.rawBuffer.isNotEmpty ? parser.rawBuffer : finalAccumulated;
  }

  Future<
    ({
      Appearance? appearance,
      Map<String, dynamic> result,
      VibeAskUserRequest? askUser,
    })
  >
  _generateAndApply(
    String turnPrompt, {
    required String systemGuide,
    List<VibeChatAttachment> attachments = const [],
  }) async {
    var currentTurnPrompt = turnPrompt;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        _pendingSnapshot = null;
        _streamingSnapshot.value = null;
      }
      final useStreaming = _usesStreamingGenerator;
      debugPrint(
        '[Vibe IA] Tentative ${attempt + 1}/4 — envoi du prompt '
        '(${currentTurnPrompt.length} caractères dynamiques, '
        'mode: ${useStreaming ? _speedMode.name : "custom"}, '
        'fichiers joints: ${attachments.length})...',
      );
      final String response;
      try {
        if (useStreaming) {
          response = await _consumeStreamingGenerate(
            currentTurnPrompt,
            systemGuide: systemGuide,
            attachments: attachments,
          );
        } else {
          final combinedPrompt =
              '${VibeChatDialog.defaultSystemInstruction}\n\n'
              'GUIDE DE MODÉLISATION :\n$systemGuide\n\n'
              '$currentTurnPrompt';
          response = await _invokeGenerate(combinedPrompt, attachments);
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[Vibe IA] Échec de génération à la tentative ${attempt + 1} '
          '(${error.runtimeType}) : $error\n$stackTrace',
        );
        rethrow;
      }
      _lastFailedResponse = response;
      _logLong('[Vibe IA] Réponse brute (tentative ${attempt + 1})', response);
      try {
        final json = _extractJson(response);
        final Object? result;
        try {
          result = jsonDecode(json);
        } on FormatException catch (error) {
          debugPrint(
            '[Vibe IA] Échec de jsonDecode (tentative ${attempt + 1}) : '
            '${error.message} (offset: ${error.offset})',
          );
          rethrow;
        }
        if (result is! Map<String, dynamic>) {
          debugPrint(
            '[Vibe IA] Le JSON décodé n’est pas un Map<String, dynamic> '
            '(type reçu: ${result.runtimeType}).',
          );
          throw const FormatException('La réponse doit être un objet JSON.');
        }
        final rawAskUser = VibeAskUserRequest.tryFromJson(result['askUser']);
        final patch = _extractPatch(result);
        if (patch == null) {
          if (rawAskUser != null &&
              (_questioningLevel == VibeQuestioningLevel.none ||
                  _isAfterAskUserReply)) {
            throw const FormatException(
              'Le questionnaire "askUser" est désactivé sur ce tour : '
              'génère directement le patch "vibe" sans "askUser".',
            );
          }
          final askUser = rawAskUser?.truncate(_questioningLevel.maxQuestions);
          final message = result['message'];
          if (askUser == null &&
              (message is! String || message.trim().isEmpty)) {
            debugPrint(
              '[Vibe IA] Réponse sans patch ni message valide. '
              'Clés reçues: ${result.keys.toList()}',
            );
            throw const FormatException(
              'La réponse ne contient ni message ni modification.',
            );
          }
          _lastFailedResponse = null;
          return (appearance: null, result: result, askUser: askUser);
        }
        final current = _currentAppearance;
        final activeScope = _scope;
        final effectivePatch = activeScope == null
            ? patch
            : VibeChatDialog.filterPatchToScope(current, patch, activeScope);
        if (activeScope != null && !_hasPatchChanges(effectivePatch)) {
          final parents = VibeChatDialog.parentIdsOfScope(current, activeScope);
          throw FormatException(
            'Modifications hors du scope autorisé (${activeScope.displayLabel}, '
            'id: "${activeScope.canonicalComponentId}"'
            '${activeScope.zoneId != null ? ', zone: "${activeScope.zoneId}"' : ''}'
            '${parents.isNotEmpty ? ', parent: "${parents.join(', ')}"' : ''}). '
            'Modifie uniquement ce scope ou son conteneur parent.',
          );
        }
        final encodedPatch = jsonEncode(effectivePatch);
        if (VibeChatDialog.verboseLogging) {
          final formattedPatch = const JsonEncoder.withIndent('  ')
              .convert(effectivePatch);
          _logLong('[Vibe IA] Patch à appliquer', formattedPatch);
        } else {
          debugPrint(
            '[Vibe IA] Patch à appliquer (${encodedPatch.length} caractères).',
          );
        }
        final Appearance appearance;
        try {
          appearance = AppearanceTransfer.applyVibe(
            current,
            encodedPatch,
            codec: widget.codec,
          );
        } catch (error, stackTrace) {
          debugPrint(
            '[Vibe IA] Échec lors de AppearanceTransfer.applyVibe '
            '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
            '$stackTrace',
          );
          rethrow;
        }
        try {
          widget.validateAppearance?.call(appearance);
        } catch (error, stackTrace) {
          debugPrint(
            '[Vibe IA] Échec lors de validateAppearance '
            '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
            '$stackTrace',
          );
          rethrow;
        }
        _validatePatchedComponents(current, appearance, effectivePatch);
        _lastFailedResponse = null;
        return (appearance: appearance, result: result, askUser: null);
      } catch (error) {
        final isValidationError =
            error is FormatException ||
            error is ArgumentError ||
            error is StateError;
        if (attempt != 0 || !isValidationError) {
          debugPrint(
            '[Vibe IA] Tentative ${attempt + 1} échouée sans relance '
            '(${error.runtimeType}) : ${_describeErrorCause(error)}',
          );
          rethrow;
        }
        final cause = _describeErrorCause(error);
        debugPrint(
          '[Vibe IA] Tentative ${attempt + 1} rejetée ($cause). '
          'Relance avec prompt de correction...',
        );
        currentTurnPrompt =
            '''
$currentTurnPrompt

CORRECTION REQUISE :
La réponse précédente a été refusée.
Cause de l'erreur (${error.runtimeType}) :
$cause
Corrige la réponse en respectant strictement le schéma JSON du guide et en rattachant tous les nouveaux composants à un conteneur existant de l'état actuel ou à une page déclarée dans pageCatalog.
Réutilise les identifiants existants ; les identifiants du guide sont uniquement des exemples.
Si tu crées une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Tu peux aussi éviter de créer une page si la demande ne le nécessite pas.
Réponse précédente invalide :
$response
''';
      }
    }
    throw StateError('La génération Vibe n’a pas produit de réponse valide.');
  }

  Map<String, dynamic>? _extractPatch(Map<String, dynamic> result) {
    if (result.containsKey('vibe') && result['vibe'] is! bool) {
      final vibe = result['vibe'];
      if (vibe == null) return null;
      if (vibe is! Map<String, dynamic>) {
        throw const FormatException(
          'Le champ "vibe" doit être un objet JSON ou null.',
        );
      }
      return _hasPatchChanges(vibe) ? vibe : null;
    }
    final candidate = Map<String, dynamic>.of(result)
      ..remove('message')
      ..remove('askUser');
    return _hasPatchChanges(candidate) ? candidate : null;
  }

  bool _hasPatchChanges(Map<String, dynamic> patch) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    const metaKeys = {'version', 'vibe', 'merge', 'format', 'groups'};
    for (final entry in payload.entries) {
      if (metaKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is Map && value.isEmpty) continue;
      return true;
    }
    return false;
  }

  void _validatePatchedComponents(
    Appearance current,
    Appearance next,
    Map<String, dynamic> patch,
  ) {
    final activeScope = _scope;
    final reachable = <String>{};
    if (activeScope != null) {
      final pending = <String>[
        ...VibeChatDialog._scopeRootIds(current, activeScope),
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        pending.addAll(
          VibeChatDialog._childrenOfComponent(next.components[id]),
        );
      }
    } else {
      final pending = [
        ...?widget.registry?.instantiatedComponentIds,
        if (widget.registry == null) ...current.components.keys,
        for (final page in next.pageCatalog.pages) page.id,
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        final component = next.components[id];
        final children = switch (component) {
          final SuperLayoutConfig layout => layout.placedSlotIds,
          final SuperListViewConfig list => list.template.placedSlotIds,
          final SuperTabConfig tab => tab.placedSlotIds,
          final SuperConditionalConfig cond => cond.placedSlotIds,
          final NativeComponentConfig native => native.placements.values.expand(
            (ids) => ids,
          ),
          final ScaffoldPageConfig scaffold =>
            scaffold.native.placements.values.expand((ids) => ids),
          _ => const <String>[],
        };
        pending.addAll(children);
      }
    }
    final payload = patch['data'] is Map ? patch['data'] as Map : patch;
    final patchedComponents = payload['components'];
    final affected = patchedComponents is Map
        ? patchedComponents.keys.whereType<String>()
        : next.components.keys.where(
            (id) => !current.components.containsKey(id),
          );
    final detached = affected
        .where(
          (id) => next.components.containsKey(id) && !reachable.contains(id),
        )
        .toList();
    if (detached.isNotEmpty) {
      debugPrint(
        '[Vibe IA] Composants détachés détectés : $detached '
        '(composants accessibles depuis l’écran : ${reachable.toList()}).',
      );
      throw FormatException(
        'Composants non rattachés à l’écran : ${detached.join(', ')}. '
        'Modifie les placements d’un conteneur existant ou déclare une page.',
      );
    }
  }

  Future<String> _loadGuide(BuildContext context) =>
      VibeChatDialog._loadGuideFromBundle(DefaultAssetBundle.of(context));

  String _buildConversationHistory() {
    final relevant = <_ChatMessage>[];
    var seenUser = false;
    for (final message in _messages) {
      if (message.isUser) {
        seenUser = true;
        relevant.add(message);
      } else if (seenUser || message.text != _initialGreetingText) {
        relevant.add(message);
      }
    }
    if (relevant.length <= _maxConversationEntries) {
      return relevant.map((m) => m.toConversationEntry()).join('\n');
    }
    final windowed = relevant.sublist(
      relevant.length - _maxConversationEntries,
    );
    if (relevant.length >= 2) {
      final preceding = relevant[relevant.length - 2];
      if (!preceding.isUser &&
          preceding.failedResponse != null &&
          !windowed.contains(preceding)) {
        windowed.insert(0, preceding);
      }
    }
    return windowed.map((m) => m.toConversationEntry()).join('\n');
  }

  String _buildTurnPrompt() {
    final conversation = _buildConversationHistory();
    final questioningDirective = _questioningLevel.promptDirective(
      afterAskUserReply: _isAfterAskUserReply,
    );
    final appearance = _currentAppearance;
    final activeScope = _scope;
    if (activeScope != null) {
      final parentIds = VibeChatDialog.parentIdsOfScope(
        appearance,
        activeScope,
      );
      final parentList = parentIds.map((id) => '"$id"').join(', ');
      final effectiveParent = parentIds.isNotEmpty
          ? parentList
          : '"${activeScope.canonicalComponentId}"';
      return '''
$questioningDirective

RESTRICTION STRICTE DE SCOPE :
L'utilisateur a ouvert l'assistant IA sur un scope restreint : "${activeScope.displayLabel}" (composant id: "${activeScope.canonicalComponentId}"${activeScope.zoneId != null ? ', zone/région: "${activeScope.zoneId}"' : ''}${parentIds.isNotEmpty ? ', conteneur parent: $parentList' : ''}).
- Le périmètre modifiable autorisé couvre l'élément sélectionné ("${activeScope.canonicalComponentId}") ainsi que son conteneur parent ($effectiveParent) et tout le sous-arbre de ce parent.
- Ne modifie AUCUN composant situé au-dessus ou en dehors du conteneur parent ($effectiveParent).
- Ne modifie PAS les paramètres globaux de thème (mode, accent, background) ni pageCatalog.
- Tout nouveau composant créé doit être rattaché dans les placements de $effectiveParent ou de l’un de ses sous-composants.

ÉTAT DU SCOPE CIBLÉ (JSON) :
${VibeChatDialog.exportScopedAi(appearance, activeScope, codec: widget.codec)}

CONVERSATION :
$conversation''';
    }

    final current = AppearanceTransfer.exportCompactAi(
      appearance,
      codec: widget.codec,
    );
    final instantiated = widget.registry?.instantiatedComponentIds;
    return [
      questioningDirective,
      if (instantiated != null)
        'Les composants instanciés sont : ${jsonEncode(instantiated.toList())}. '
            'Rattache les modifications à ces composants ou aux pages déclarées ; '
            'une configuration sauvegardée mais isolée ne suffit pas.',
      'ÉTAT ACTUEL (JSON) :\n$current',
      'CONVERSATION :\n$conversation',
    ].join('\n\n');
  }

  static IconData _iconForSpeedMode(VibeAiSpeedMode mode) => switch (mode) {
    VibeAiSpeedMode.ultraFast => Icons.bolt,
    VibeAiSpeedMode.fast => Icons.flash_on,
    VibeAiSpeedMode.reasoning => Icons.psychology_outlined,
  };

  static IconData _iconForQuestioningLevel(VibeQuestioningLevel level) =>
      switch (level) {
        VibeQuestioningLevel.none => Icons.speaker_notes_off_outlined,
        VibeQuestioningLevel.light => Icons.help_outline,
        VibeQuestioningLevel.balanced => Icons.quiz_outlined,
        VibeQuestioningLevel.thorough => Icons.fact_check_outlined,
      };

  String _extractJson(String response) {
    var value = response.trim();
    if (value.startsWith('```')) {
      final newline = value.indexOf('\n');
      if (newline < 0) {
        throw const FormatException('Aucun objet JSON détecté.');
      }
      value = value.substring(newline + 1).trim();
      if (value.endsWith('```')) {
        value = value.substring(0, value.length - 3).trim();
      }
    }
    return value;
  }

  void _appendMessage(
    String text, {
    String? failedResponse,
    VibeAskUserRequest? askUser,
  }) {
    if (!mounted) return;
    setState(
      () => _messages.add(
        _ChatMessage(
          text: text,
          isUser: false,
          failedResponse: failedResponse,
          askUser: askUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('vibe-chat-dialog'),
      color: scheme.surface,
      elevation: 18,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('vibe-chat-drag'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => widget.onDrag(details.delta),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: scheme.primary,
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vibe — création d’écran',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.drag_indicator, color: scheme.onPrimary, size: 18),
                  IconButton(
                    key: const ValueKey('vibe-chat-close'),
                    tooltip: 'Fermer le chat',
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close, color: scheme.onPrimary, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(
              'Votre demande et la configuration de l’écran sont envoyées à Gemini.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, mode)
                        in VibeAiSpeedMode.values.indexed) ...[
                      if (index > 0) const SizedBox(width: 6),
                      _SpeedModeChip(
                        mode: mode,
                        icon: _iconForSpeedMode(mode),
                        selected: _speedMode == mode,
                        enabled: !_sending,
                        onSelected: () => _setSpeedMode(mode),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            key: const ValueKey('vibe-chat-questioning-row'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            child: Row(
              children: [
                Icon(
                  _iconForQuestioningLevel(_questioningLevel),
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  'Questions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6.5,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      key: const ValueKey('vibe-chat-questioning-slider'),
                      value: _questioningLevel.index.toDouble(),
                      min: 0,
                      max: 3,
                      divisions: 3,
                      label: _questioningLevel.label,
                      onChanged: _sending
                          ? null
                          : (value) => _setQuestioningLevel(
                              VibeQuestioningLevel.fromSliderValue(value),
                            ),
                    ),
                  ),
                ),
                Tooltip(
                  message: _questioningLevel.tooltip,
                  child: Container(
                    key: const ValueKey('vibe-chat-questioning-label'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _questioningLevel == VibeQuestioningLevel.none
                          ? scheme.surfaceContainerHighest
                          : scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _questioningLevel.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _questioningLevel == VibeQuestioningLevel.none
                            ? scheme.onSurfaceVariant
                            : scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_scope case final activeScope?)
            Container(
              key: const ValueKey('vibe-chat-scope-banner'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_center_focus_outlined,
                    size: 16,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scope : ${activeScope.displayLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('vibe-chat-clear-scope'),
                    tooltip: 'Retirer la restriction de scope',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    color: scheme.onSecondaryContainer,
                    onPressed: _sending ? null : _clearScope,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.all(12),
              children: [
                if (_sending)
                  _StreamingAssistantBubble(snapshot: _streamingSnapshot),
                for (var i = _messages.length - 1; i >= 0; i--)
                  _MessageBubble(
                    message: _messages[i],
                    sending: _sending,
                    onSubmitAskUser: (answers) =>
                        _submitAskUser(i, answers, usedDefaults: false),
                    onSkipAskUser: () {
                      final askUser = _messages[i].askUser;
                      if (askUser == null) return;
                      _submitAskUser(
                        i,
                        askUser.defaultAnswers(),
                        usedDefaults: true,
                      );
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_attachmentError != null)
            Container(
              key: const ValueKey('vibe-chat-attachment-error'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: scheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachmentError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    color: scheme.onErrorContainer,
                    onPressed: () => setState(() => _attachmentError = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (_pendingAttachments.isNotEmpty)
            Container(
              key: const ValueKey('vibe-chat-pending-attachments'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (index, attachment)
                        in _pendingAttachments.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _PendingAttachmentChip(
                          index: index,
                          attachment: attachment,
                          onRemove: _sending
                              ? null
                              : () => _removePendingAttachment(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('vibe-chat-attach'),
                  tooltip: 'Joindre un fichier (image ou texte)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachFromPicker,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  key: const ValueKey('vibe-chat-paste-attachment'),
                  tooltip: 'Coller un fichier ou texte du presse-papiers',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachFromClipboard,
                  icon: const Icon(Icons.content_paste),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    key: const ValueKey('vibe-chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Décris l’écran souhaité…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('vibe-chat-send'),
                  tooltip: 'Générer et appliquer',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.promptText,
    this.failedResponse,
    this.attachments = const [],
    this.askUser,
    this.askUserAnswers,
    this.askUserUsedDefaults = false,
    this.askUserDismissed = false,
  });

  final String text;
  final bool isUser;
  final String? promptText;
  final String? failedResponse;
  final List<VibeChatAttachment> attachments;
  final VibeAskUserRequest? askUser;
  final Map<String, Object?>? askUserAnswers;
  final bool askUserUsedDefaults;
  final bool askUserDismissed;

  _ChatMessage copyWith({
    String? text,
    bool? isUser,
    String? promptText,
    String? failedResponse,
    List<VibeChatAttachment>? attachments,
    VibeAskUserRequest? askUser,
    Map<String, Object?>? askUserAnswers,
    bool? askUserUsedDefaults,
    bool? askUserDismissed,
  }) => _ChatMessage(
    text: text ?? this.text,
    isUser: isUser ?? this.isUser,
    promptText: promptText ?? this.promptText,
    failedResponse: failedResponse ?? this.failedResponse,
    attachments: attachments ?? this.attachments,
    askUser: askUser ?? this.askUser,
    askUserAnswers: askUserAnswers ?? this.askUserAnswers,
    askUserUsedDefaults: askUserUsedDefaults ?? this.askUserUsedDefaults,
    askUserDismissed: askUserDismissed ?? this.askUserDismissed,
  );

  String toConversationEntry() {
    if (isUser) {
      final effectiveText = text.isEmpty && attachments.isNotEmpty
          ? 'Analyse les fichiers joints et applique les modifications correspondantes.'
          : text;
      final promptBody = promptText ?? effectiveText;
      if (attachments.isEmpty) {
        return 'Utilisateur : $promptBody';
      }
      final buffer = StringBuffer('Utilisateur : $promptBody');
      for (final attachment in attachments) {
        if (attachment.isImage) {
          buffer.write(
            '\n[Fichier image joint : "${attachment.name}" (${attachment.mimeType})]',
          );
        } else if (attachment.isText) {
          buffer.write(
            '\n[Fichier texte joint : "${attachment.name}" (${attachment.mimeType})]\n'
            '${attachment.textContent}',
          );
        }
      }
      return buffer.toString();
    }
    final rejected = failedResponse?.trim();
    if (rejected == null || rejected.isEmpty) {
      if (askUser != null) {
        return 'Assistant : $text\n'
            'Questions posées : ${jsonEncode(askUser!.toJson())}';
      }
      return 'Assistant : $text';
    }
    return 'Assistant (ERREUR À CORRIGER) : $text\n'
        'Réponse précédente invalide :\n$rejected';
  }
}

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final int index;
  final VibeChatAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('vibe-chat-pending-attachment-$index'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  attachment.bytes,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              )
            else
              Icon(
                Icons.description_outlined,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              key: ValueKey('vibe-chat-remove-attachment-$index'),
              tooltip: 'Retirer ${attachment.name}',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              onPressed: onRemove,
              icon: Icon(
                Icons.close,
                size: 15,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.sending = false,
    this.onSubmitAskUser,
    this.onSkipAskUser,
  });

  final _ChatMessage message;
  final bool sending;
  final ValueChanged<Map<String, Object?>>? onSubmitAskUser;
  final VoidCallback? onSkipAskUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = message.isUser
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final askUser = message.askUser;
    final isResolvedAskUser =
        message.askUserAnswers != null || message.askUserDismissed;

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.attachments.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final attachment in message.attachments)
                    if (attachment.isImage)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 220,
                                maxHeight: 120,
                              ),
                              child: Image.memory(
                                attachment.bytes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  padding: const EdgeInsets.all(8),
                                  color: scheme.surface.withValues(alpha: 0.4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.image_outlined,
                                        size: 16,
                                        color: foreground,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          attachment.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: foreground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            attachment.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: foreground.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 15,
                              color: foreground,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                attachment.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: foreground,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
              if (message.text.isNotEmpty) const SizedBox(height: 6),
            ],
            if (message.text.isNotEmpty) SelectableText(message.text),
            if (askUser != null) ...[
              if (message.text.isNotEmpty) const SizedBox(height: 8),
              if (isResolvedAskUser)
                _ResolvedAskUserBadge(
                  dismissed: message.askUserDismissed,
                  usedDefaults: message.askUserUsedDefaults,
                )
              else
                _AskUserCard(
                  key: const ValueKey('vibe-ask-user-card'),
                  request: askUser,
                  sending: sending,
                  onSubmit: onSubmitAskUser ?? (_) {},
                  onSkip: onSkipAskUser ?? () {},
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResolvedAskUserBadge extends StatelessWidget {
  const _ResolvedAskUserBadge({
    required this.dismissed,
    required this.usedDefaults,
  });

  final bool dismissed;
  final bool usedDefaults;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label) = dismissed
        ? (Icons.remove_circle_outline, 'Questionnaire ignoré')
        : usedDefaults
        ? (Icons.fast_forward_outlined, 'Valeurs par défaut appliquées')
        : (Icons.check_circle_outline, 'Réponses envoyées');

    return Container(
      key: const ValueKey('vibe-ask-user-resolved'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AskUserCard extends StatefulWidget {
  const _AskUserCard({
    required this.request,
    required this.sending,
    required this.onSubmit,
    required this.onSkip,
    super.key,
  });

  final VibeAskUserRequest request;
  final bool sending;
  final ValueChanged<Map<String, Object?>> onSubmit;
  final VoidCallback onSkip;

  @override
  State<_AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<_AskUserCard> {
  final Map<String, String> _singleSelected = <String, String>{};
  final Map<String, Set<String>> _multiSelected = <String, Set<String>>{};
  final Map<String, bool> _boolValues = <String, bool>{};
  final Map<String, bool> _otherSelected = <String, bool>{};
  final Map<String, TextEditingController> _otherControllers =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _initFields();
  }

  @override
  void didUpdateWidget(_AskUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _disposeControllers();
      _singleSelected.clear();
      _multiSelected.clear();
      _boolValues.clear();
      _otherSelected.clear();
      _initFields();
    }
  }

  void _initFields() {
    for (final q in widget.request.questions) {
      switch (q.type) {
        case VibeAskUserFieldType.single:
          final initial = q.effectiveInitialAnswer() as String;
          if (q.options.contains(initial)) {
            _singleSelected[q.id] = initial;
            _otherSelected[q.id] = false;
            if (q.allowOther) {
              _otherControllers[q.id] = TextEditingController();
            }
          } else if (initial.isNotEmpty && q.allowOther) {
            _singleSelected[q.id] = q.options.isNotEmpty ? q.options.first : '';
            _otherSelected[q.id] = true;
            _otherControllers[q.id] = TextEditingController(text: initial);
          } else {
            _singleSelected[q.id] = q.options.isNotEmpty ? q.options.first : '';
            _otherSelected[q.id] = false;
            if (q.allowOther) {
              _otherControllers[q.id] = TextEditingController();
            }
          }
        case VibeAskUserFieldType.multi:
          final initialList = q.effectiveInitialAnswer() as List<String>;
          final selectedSet = <String>{
            for (final item in initialList)
              if (q.options.contains(item)) item,
          };
          final customItems = <String>[
            for (final item in initialList)
              if (!q.options.contains(item)) item,
          ];
          _multiSelected[q.id] = selectedSet;
          if (q.allowOther) {
            final hasCustom = customItems.isNotEmpty;
            _otherSelected[q.id] = hasCustom;
            _otherControllers[q.id] = TextEditingController(
              text: hasCustom ? customItems.join(', ') : '',
            );
          } else {
            _otherSelected[q.id] = false;
          }
        case VibeAskUserFieldType.boolean:
          _boolValues[q.id] = q.effectiveInitialAnswer() as bool;
        case VibeAskUserFieldType.text:
          _textControllers[q.id] = TextEditingController(
            text: q.effectiveInitialAnswer() as String,
          );
      }
    }
  }

  void _disposeControllers() {
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    _otherControllers.clear();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  Map<String, Object?> _collectAnswers() {
    final answers = <String, Object?>{};
    for (final q in widget.request.questions) {
      switch (q.type) {
        case VibeAskUserFieldType.single:
          if (_otherSelected[q.id] ?? false) {
            final custom = _otherControllers[q.id]?.text.trim() ?? '';
            answers[q.id] = custom.isNotEmpty
                ? custom
                : q.effectiveInitialAnswer();
          } else {
            final chosen = _singleSelected[q.id] ?? '';
            answers[q.id] = chosen.isNotEmpty
                ? chosen
                : q.effectiveInitialAnswer();
          }
        case VibeAskUserFieldType.multi:
          final selectedSet = _multiSelected[q.id] ?? const <String>{};
          final items = <String>[
            for (final opt in q.options)
              if (selectedSet.contains(opt)) opt,
          ];
          if (_otherSelected[q.id] ?? false) {
            final custom = _otherControllers[q.id]?.text.trim() ?? '';
            if (custom.isNotEmpty && !items.contains(custom)) {
              items.add(custom);
            }
          }
          answers[q.id] = List<String>.unmodifiable(items);
        case VibeAskUserFieldType.boolean:
          answers[q.id] =
              _boolValues[q.id] ?? (q.effectiveInitialAnswer() as bool);
        case VibeAskUserFieldType.text:
          answers[q.id] = (_textControllers[q.id]?.text ?? '').trim();
      }
    }
    return answers;
  }

  void _handleSubmit() {
    if (widget.sending) return;
    widget.onSubmit(_collectAnswers());
  }

  Widget _buildQuestionControl(BuildContext context, VibeAskUserQuestion q) {
    final scheme = Theme.of(context).colorScheme;
    switch (q.type) {
      case VibeAskUserFieldType.single:
        final isOther = _otherSelected[q.id] ?? false;
        final currentOpt = _singleSelected[q.id];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (optIndex, opt) in q.options.indexed)
                  ChoiceChip(
                    key: ValueKey('vibe-ask-option-${q.id}-$optIndex'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      opt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: !isOther && currentOpt == opt,
                    onSelected: widget.sending
                        ? null
                        : (_) => setState(() {
                            _otherSelected[q.id] = false;
                            _singleSelected[q.id] = opt;
                          }),
                  ),
                if (q.allowOther)
                  ChoiceChip(
                    key: ValueKey('vibe-ask-other-chip-${q.id}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: const Text('Autre…', style: TextStyle(fontSize: 12)),
                    selected: isOther,
                    onSelected: widget.sending
                        ? null
                        : (selected) => setState(() {
                            _otherSelected[q.id] = selected;
                          }),
                  ),
              ],
            ),
            if (q.allowOther && isOther) ...[
              const SizedBox(height: 6),
              TextField(
                key: ValueKey('vibe-ask-other-input-${q.id}'),
                controller: _otherControllers[q.id],
                enabled: !widget.sending,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Préciser…',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ],
        );

      case VibeAskUserFieldType.multi:
        final selectedSet = _multiSelected.putIfAbsent(q.id, () => <String>{});
        final isOther = _otherSelected[q.id] ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (optIndex, opt) in q.options.indexed)
                  FilterChip(
                    key: ValueKey('vibe-ask-option-${q.id}-$optIndex'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      opt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: selectedSet.contains(opt),
                    onSelected: widget.sending
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              selectedSet.add(opt);
                            } else {
                              selectedSet.remove(opt);
                            }
                          }),
                  ),
                if (q.allowOther)
                  FilterChip(
                    key: ValueKey('vibe-ask-other-chip-${q.id}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: const Text('Autre…', style: TextStyle(fontSize: 12)),
                    selected: isOther,
                    onSelected: widget.sending
                        ? null
                        : (selected) => setState(() {
                            _otherSelected[q.id] = selected;
                          }),
                  ),
              ],
            ),
            if (q.allowOther && isOther) ...[
              const SizedBox(height: 6),
              TextField(
                key: ValueKey('vibe-ask-other-input-${q.id}'),
                controller: _otherControllers[q.id],
                enabled: !widget.sending,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Autre choix…',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ],
        );

      case VibeAskUserFieldType.boolean:
        final value = _boolValues[q.id] ?? (q.effectiveInitialAnswer() as bool);
        return Row(
          children: [
            Expanded(
              child: Text(
                value ? 'Oui' : 'Non',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
              ),
            ),
            Switch(
              key: ValueKey('vibe-ask-switch-${q.id}'),
              value: value,
              onChanged: widget.sending
                  ? null
                  : (next) => setState(() => _boolValues[q.id] = next),
            ),
          ],
        );

      case VibeAskUserFieldType.text:
        return TextField(
          key: ValueKey('vibe-ask-text-${q.id}'),
          controller: _textControllers[q.id],
          enabled: !widget.sending,
          style: const TextStyle(fontSize: 12.5),
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (qIndex, q) in widget.request.questions.indexed) ...[
            if (qIndex > 0) const SizedBox(height: 10),
            Text(
              q.title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (q.description != null && q.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                q.description!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 6),
            _buildQuestionControl(context, q),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Tooltip(
                  message: 'Générer avec les valeurs par défaut',
                  child: TextButton(
                    key: const ValueKey('vibe-ask-user-skip'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.sending ? null : widget.onSkip,
                    child: const Text('Passer'),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('vibe-ask-user-submit'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.sending ? null : _handleSubmit,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Générer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedModeChip extends StatelessWidget {
  const _SpeedModeChip({
    required this.mode,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final VibeAiSpeedMode mode;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    return Tooltip(
      message: mode.tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: mode.label,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('vibe-chat-speed-${mode.name}'),
            onTap: enabled ? onSelected : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamingAssistantBubble extends StatelessWidget {
  const _StreamingAssistantBubble({required this.snapshot});

  final ValueListenable<VibeStreamSnapshot?> snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      key: const ValueKey('vibe-chat-streaming-bubble'),
      alignment: Alignment.centerLeft,
      child: ValueListenableBuilder<VibeStreamSnapshot?>(
        valueListenable: snapshot,
        builder: (context, current, _) {
          final streamedMessage = current?.message;
          if (current == null || streamedMessage == null) {
            return Container(
              constraints: const BoxConstraints(maxWidth: 340),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Génération en cours…',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final count = current.estimatedComponentCount;
          final patchLabel = count > 0
              ? 'Construction du patch UI ($count composant${count > 1 ? 's' : ''})…'
              : 'Construction du patch UI…';

          return Container(
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(streamedMessage),
                if (current.hasVibeObject) ...[
                  if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          patchLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (current.isMessageComplete &&
                    current.hasAskUserObject) ...[
                  if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Préparation des questions…',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
