import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../services/appearance/appearance_codec.dart';
import '../../services/appearance/appearance_transfer.dart';
import '../../theme/appearance.dart';

class VibeChatDialog extends StatefulWidget {
  const VibeChatDialog({
    required this.controller,
    required this.codec,
    required this.onClose,
    required this.onDrag,
    required this.generate,
    this.validateAppearance,
    this.registry,
    super.key,
  });

  final ValueNotifier<Appearance> controller;
  final AppearanceCodec codec;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;
  final Future<String> Function(String prompt) generate;
  final void Function(Appearance appearance)? validateAppearance;
  final Registry? registry;

  @override
  State<VibeChatDialog> createState() => _VibeChatDialogState();
}

class _VibeChatDialogState extends State<VibeChatDialog> {
  static const _guideAssets = [
    'SCREEN_JSON_AI_GUIDE.md',
    'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
  ];

  final _input = TextEditingController();
  final _messages = <_ChatMessage>[
    const _ChatMessage(
      text: 'Décris l’écran à créer ou les changements souhaités.',
      isUser: false,
    ),
  ];
  bool _sending = false;

  Appearance get _currentAppearance =>
      widget.registry?.appearanceSnapshot(widget.controller.value) ??
      widget.controller.value;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final request = _input.text.trim();
    if (request.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(text: request, isUser: true));
    });

    try {
      final guide = await _loadGuide(context);
      final generated = await _generateAndApply(_buildPrompt(guide));
      widget.controller.value = generated.appearance;
      final summary = generated.result['message'];
      _appendMessage(
        summary is String && summary.trim().isNotEmpty
            ? summary.trim()
            : 'Modifications appliquées.',
      );
    } on FormatException catch (error) {
      _appendMessage('Réponse Vibe invalide : ${error.message}');
    } on ArgumentError catch (error) {
      _appendMessage('Modification refusée : ${error.message}');
    } on StateError catch (error) {
      _appendMessage('Modification impossible : ${error.message}');
    } on FlutterError catch (error) {
      debugPrint('AI screen guide could not be loaded: $error');
      _appendMessage('Guide de génération indisponible : ${error.message}');
    } on Exception catch (error) {
      debugPrint('AI screen generation failed: $error');
      _appendMessage('Génération impossible : $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<({Appearance appearance, Map<String, dynamic> result})>
  _generateAndApply(String prompt) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await widget.generate(prompt);
      debugPrint('[Vibe IA] Réponse brute (tentative ${attempt + 1}) :');
      debugPrint(response);
      try {
        final json = _extractJson(response);
        final result = jsonDecode(json);
        if (result is! Map<String, dynamic>) {
          throw const FormatException('La réponse doit être un objet JSON.');
        }
        final vibe = result['vibe'];
        final patch = vibe is Map<String, dynamic> ? vibe : result;
        debugPrint('[Vibe IA] Patch à appliquer :');
        debugPrint(const JsonEncoder.withIndent('  ').convert(patch));
        final current = _currentAppearance;
        final appearance = AppearanceTransfer.applyVibe(
          current,
          jsonEncode(patch),
          codec: widget.codec,
        );
        widget.validateAppearance?.call(appearance);
        _validatePatchedComponents(current, appearance, patch);
        return (appearance: appearance, result: result);
      } on FormatException catch (error) {
        if (attempt != 0 ||
            (!_isInvalidPagePath(error) &&
                !error.message.startsWith('Composants non rattachés'))) {
          rethrow;
        }
        prompt =
            '''
$prompt

CORRECTION REQUISE :
La réponse précédente a été refusée :
${error.message}
Corrige la réponse en rattachant tous les nouveaux composants à un conteneur existant de l'état actuel ou à une page déclarée dans pageCatalog.
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

  bool _isInvalidPagePath(FormatException error) => error.message.contains(
    'Chemin absolu requis, différent de /, sans espace ni fragment.',
  );

  void _validatePatchedComponents(
    Appearance current,
    Appearance next,
    Map<String, dynamic> patch,
  ) {
    final reachable = <String>{};
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
        final NativeComponentConfig native => native.placements.values.expand(
          (ids) => ids,
        ),
        final ScaffoldPageConfig scaffold =>
          scaffold.native.placements.values.expand((ids) => ids),
        _ => const <String>[],
      };
      pending.addAll(children);
    }
    final payload = patch['data'] is Map ? patch['data'] as Map : patch;
    final patchedComponents = payload['components'];
    final affected = patchedComponents is Map
        ? patchedComponents.keys.whereType<String>()
        : next.components.keys.where(
            (id) => !current.components.containsKey(id),
          );
    final detached = affected.where(
      (id) => next.components.containsKey(id) && !reachable.contains(id),
    );
    if (detached.isNotEmpty) {
      throw FormatException(
        'Composants non rattachés à l’écran : ${detached.join(', ')}. '
        'Modifie les placements d’un conteneur existant ou déclare une page.',
      );
    }
  }

  Future<String> _loadGuide(BuildContext context) async {
    final bundle = DefaultAssetBundle.of(context);
    FlutterError? lastError;
    for (final asset in _guideAssets) {
      try {
        final guide = await bundle.loadString(asset);
        if (guide.trim().isNotEmpty) return guide;
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

  String _buildPrompt(String guide) {
    final conversation = _messages
        .map(
          (message) =>
              '${message.isUser ? 'Utilisateur' : 'Assistant'} : ${message.text}',
        )
        .join('\n');
    final current = AppearanceTransfer.exportAi(
      _currentAppearance,
      codec: widget.codec,
    );
    final instantiated = widget.registry?.instantiatedComponentIds;
    return '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide ci-dessous et l’état actuel de l’application.
Renvoie uniquement un objet JSON de la forme {"message":"résumé bref en français","vibe":{...}}.
Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
Réutilise les identifiants des conteneurs de l'état actuel, y compris ceux dont la configuration est encore celle par défaut. Les identifiants du guide (comme "contA") sont des exemples, pas des racines d'écran implicites.
Tout nouveau composant doit être rattaché par les placements à un conteneur existant ou à une page déclarée dans pageCatalog. Créer un layout isolé ne l'affiche pas.
${instantiated == null ? '' : 'Les composants instanciés sont : ${jsonEncode(instantiated.toList())}. Rattache les modifications à ces composants ou aux pages déclarées ; une configuration sauvegardée mais isolée ne suffit pas.'}
Si une opération crée une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Ne renvoie aucun Markdown ni texte hors du JSON. Si une information manque, fais une hypothèse raisonnable et indique-la dans "message".

GUIDE DE MODÉLISATION :
$guide

ÉTAT ACTUEL (JSON) :
$current

CONVERSATION :
$conversation
''';
  }

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

  void _appendMessage(String text) {
    if (!mounted) return;
    setState(() => _messages.add(_ChatMessage(text: text, isUser: false)));
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
              height: 52,
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Votre demande et la configuration de l’écran sont envoyées à Gemini.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.all(12),
              children: [
                if (_sending)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                for (final message in _messages.reversed)
                  _MessageBubble(message: message),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
  const _ChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        child: SelectableText(message.text),
      ),
    );
  }
}
