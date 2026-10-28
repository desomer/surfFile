import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../ai/vibe_chat_attachment.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../theme/appearance.dart';

export '../../../ai/vibe_chat_attachment.dart';

class VibeChatDialog extends StatefulWidget {
  const VibeChatDialog({
    required this.controller,
    required this.codec,
    required this.onClose,
    required this.onDrag,
    required this.generate,
    this.pickAttachments,
    this.pasteAttachments,
    this.validateAppearance,
    this.registry,
    super.key,
  });

  final ValueNotifier<Appearance> controller;
  final AppearanceCodec codec;
  final VoidCallback onClose;
  final ValueChanged<Offset> onDrag;
  final Future<String> Function(String prompt) generate;
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
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
  final _pendingAttachments = <VibeChatAttachment>[];
  final _messages = <_ChatMessage>[
    const _ChatMessage(
      text: 'Décris l’écran à créer ou les changements souhaités.',
      isUser: false,
    ),
  ];
  bool _sending = false;
  String? _lastFailedResponse;
  String? _attachmentError;

  Appearance get _currentAppearance =>
      widget.registry?.appearanceSnapshot(widget.controller.value) ??
      widget.controller.value;

  @override
  void dispose() {
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
      final paster = widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
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
    _lastFailedResponse = null;
    setState(() {
      _sending = true;
      _pendingAttachments.clear();
      _attachmentError = null;
      _messages.add(
        _ChatMessage(
          text: request,
          isUser: true,
          attachments: attachments,
        ),
      );
    });

    debugPrint(
      '[Vibe IA] Nouvelle demande utilisateur : "$request" '
      '(pièces jointes: ${attachments.map((a) => a.name).toList()})',
    );
    try {
      final guide = await _loadGuide(context);
      final prompt = _buildPrompt(guide);
      final allAttachments = <VibeChatAttachment>[
        for (final message in _messages)
          if (message.isUser) ...message.attachments,
      ];
      final generated = await _generateAndApply(
        prompt,
        attachments: allAttachments,
      );
      if (generated.appearance case final appearance?) {
        widget.controller.value = appearance;
        debugPrint(
          '[Vibe IA] Apparence mise à jour avec succès '
          '(composants: ${appearance.components.length}, '
          'styles: ${appearance.styles.length}, '
          'pages: ${appearance.pageCatalog.pages.length}).',
        );
      } else {
        debugPrint(
          '[Vibe IA] Réponse textuelle affichée sans modification d’apparence.',
        );
      }
      final summary = generated.result['message'];
      _appendMessage(
        summary is String && summary.trim().isNotEmpty
            ? summary.trim()
            : 'Modifications appliquées.',
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
      if (mounted) setState(() => _sending = false);
    }
  }

  void _logLong(String title, String content) {
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
    if (generator is Future<String> Function(
      String, {
      List<VibeChatAttachment> attachments,
    })) {
      return generator(prompt, attachments: attachments);
    }
    return generator(prompt);
  }

  Future<({Appearance? appearance, Map<String, dynamic> result})>
  _generateAndApply(
    String prompt, {
    List<VibeChatAttachment> attachments = const [],
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      debugPrint(
        '[Vibe IA] Tentative ${attempt + 1}/2 — envoi du prompt '
        '(${prompt.length} caractères, '
        'fichiers joints: ${attachments.length})...',
      );
      final String response;
      try {
        response = await _invokeGenerate(prompt, attachments);
      } catch (error, stackTrace) {
        debugPrint(
          '[Vibe IA] Échec de widget.generate à la tentative ${attempt + 1} '
          '(${error.runtimeType}) : $error\n$stackTrace',
        );
        rethrow;
      }
      _lastFailedResponse = response;
      _logLong(
        '[Vibe IA] Réponse brute (tentative ${attempt + 1})',
        response,
      );
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
        final patch = _extractPatch(result);
        if (patch == null) {
          final message = result['message'];
          if (message is! String || message.trim().isEmpty) {
            debugPrint(
              '[Vibe IA] Réponse sans patch ni message valide. '
              'Clés reçues: ${result.keys.toList()}',
            );
            throw const FormatException(
              'La réponse ne contient ni message ni modification.',
            );
          }
          _lastFailedResponse = null;
          return (appearance: null, result: result);
        }
        final formattedPatch = const JsonEncoder.withIndent('  ').convert(
          patch,
        );
        _logLong('[Vibe IA] Patch à appliquer', formattedPatch);
        final current = _currentAppearance;
        final Appearance appearance;
        try {
          appearance = AppearanceTransfer.applyVibe(
            current,
            jsonEncode(patch),
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
        _validatePatchedComponents(current, appearance, patch);
        _lastFailedResponse = null;
        return (appearance: appearance, result: result);
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
        prompt =
            '''
$prompt

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
    final candidate = Map<String, dynamic>.of(result)..remove('message');
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
        final SuperTabConfig tab => tab.placedSlotIds,
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
        .map((message) => message.toConversationEntry())
        .join('\n');
    final current = AppearanceTransfer.exportAi(
      _currentAppearance,
      codec: widget.codec,
    );
    final instantiated = widget.registry?.instantiatedComponentIds;
    return '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide ci-dessous et l’état actuel de l’application.
Renvoie uniquement un objet JSON :
- Si l'utilisateur demande de créer ou modifier l'écran, renvoie {"message":"résumé bref en français","vibe":{...}}. Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
- Si l'utilisateur pose une question ou demande une information sans demander de modification de l'écran, renvoie {"message":"réponse claire en français","vibe":null} (ou omets le champ "vibe") sans modifier l'écran.
Réutilise les identifiants des conteneurs de l'état actuel, y compris ceux dont la configuration est encore celle par défaut. Les identifiants du guide (comme "contA") sont des exemples, pas des racines d'écran implicites.
Tout nouveau composant doit être rattaché par les placements à un conteneur existant ou à une page déclarée dans pageCatalog. Créer un layout isolé ne l'affiche pas.
${instantiated == null ? '' : 'Les composants instanciés sont : ${jsonEncode(instantiated.toList())}. Rattache les modifications à ces composants ou aux pages déclarées ; une configuration sauvegardée mais isolée ne suffit pas.'}
Si une opération crée une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Si la conversation mentionne une erreur sur une réponse précédente, identifie la cause indiquée et corrige-la sans reproduire la même erreur.
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

  void _appendMessage(String text, {String? failedResponse}) {
    if (!mounted) return;
    setState(
      () => _messages.add(
        _ChatMessage(
          text: text,
          isUser: false,
          failedResponse: failedResponse,
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
            padding: const EdgeInsets.all(10),
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
    this.failedResponse,
    this.attachments = const [],
  });

  final String text;
  final bool isUser;
  final String? failedResponse;
  final List<VibeChatAttachment> attachments;

  String toConversationEntry() {
    if (isUser) {
      final effectiveText = text.isEmpty && attachments.isNotEmpty
          ? 'Analyse les fichiers joints et applique les modifications correspondantes.'
          : text;
      if (attachments.isEmpty) {
        return 'Utilisateur : $effectiveText';
      }
      final buffer = StringBuffer('Utilisateur : $effectiveText');
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
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = message.isUser
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
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
          ],
        ),
      ),
    );
  }
}
