/// Panneau de chat global pour poser des questions transverses sur l'ensemble du projet ([GlobalQuestionChatPane]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_project.dart';
import '../models/spec_stage_chat.dart';
import '../services/spec_forge_controller.dart';

/// Chat IA dédié aux questions globales sur le projet (lexique, cadrage, cahier des charges, objets et règles).
class GlobalQuestionChatPane extends StatefulWidget {
  /// Crée le panneau connecté au [controller].
  const GlobalQuestionChatPane({
    required this.controller,
    this.onNavigateToSpec,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Callback optionnel pour revenir vers l'onglet Spec si aucun projet n'est ouvert.
  final VoidCallback? onNavigateToSpec;

  /// Sélecteur optionnel de fichiers.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant la présence de média dans le presse-papiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers sur `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<GlobalQuestionChatPane> createState() => _GlobalQuestionChatPaneState();
}

class _GlobalQuestionChatPaneState extends State<GlobalQuestionChatPane> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<VibeChatAttachment> _pendingAttachments = [];
  String? _attachmentError;
  int _lastCount = 0;

  static const List<String> _suggestedQuestions = [
    'Résume l’architecture métier, les acteurs et les règles critiques.',
    'Quelles incohérences ou zones d’ombre restent à traiter ?',
    'Quelles règles de gestion RG-xxx s’appliquent à chaque objet métier ?',
    'Le vocabulaire du lexique est-il bien respecté partout ?',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _appendPendingAttachments(Iterable<VibeChatAttachment> incoming) {
    final usedNames = <String>{for (final a in _pendingAttachments) a.name};
    for (final attachment in incoming) {
      var candidateName = attachment.name;
      if (usedNames.contains(candidateName)) {
        final dot = candidateName.lastIndexOf('.');
        final stem = dot > 0 ? candidateName.substring(0, dot) : candidateName;
        final ext = dot > 0 ? candidateName.substring(dot) : '';
        var suffix = 2;
        while (usedNames.contains('$stem-$suffix$ext')) {
          suffix++;
        }
        candidateName = '$stem-$suffix$ext';
      }
      usedNames.add(candidateName);
      _pendingAttachments.add(
        candidateName == attachment.name
            ? attachment
            : attachment.withName(candidateName),
      );
    }
  }

  Future<void> _attachFromPicker() async {
    if (widget.controller.isSending) return;
    setState(() => _attachmentError = null);
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      setState(() => _appendPendingAttachments(picked));
    } on FormatException catch (e) {
      if (mounted) setState(() => _attachmentError = e.message);
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() => _attachmentError = 'Lecture impossible : ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _attachmentError = 'Import impossible : $e');
      }
    }
  }

  Future<void> _attachFromClipboard() async {
    if (widget.controller.isSending) return;
    setState(() => _attachmentError = null);
    try {
      final paster = widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucune image, fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() => _appendPendingAttachments(pasted));
    } catch (e) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Collage presse-papiers impossible : $e',
        );
      }
    }
  }

  Future<void> _attachMediaFromShortcut() async {
    if (widget.controller.isSending) return;
    try {
      final paster =
          widget.pasteClipboardMedia ??
          (widget.hasClipboardMedia != null ? widget.pasteAttachments : null) ??
          VibeChatAttachment.fromClipboardImagesOrFiles;
      final pasted = await paster();
      if (!mounted || pasted.isEmpty) return;
      setState(() => _appendPendingAttachments(pasted));
    } catch (_) {}
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.controller.isSending || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !keyboard.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    final isCtrlOrMetaV =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    if (!isCtrlOrMetaV) return KeyEventResult.ignored;

    final hasMedia =
        (widget.hasClipboardMedia ??
            VibeChatAttachment.hasClipboardImageOrFiles)();
    if (!hasMedia) return KeyEventResult.ignored;
    unawaited(_attachMediaFromShortcut());
    return KeyEventResult.handled;
  }

  void _send([String? quickPrompt]) {
    if (widget.controller.isSending) return;
    final text = (quickPrompt ?? _inputController.text).trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    if (quickPrompt == null) {
      _inputController.clear();
    }
    setState(() {
      _pendingAttachments.clear();
      _attachmentError = null;
    });
    widget.controller.sendGlobalQuestion(text, attachments: attachments);
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (project == null) {
      return Center(
        key: const ValueKey('spec-global-chat-no-project'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.question_answer_outlined,
                size: 48,
                color: colors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Aucun projet ouvert',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Créez ou reprenez un projet dans l’onglet Spec pour poser des questions globales dessus.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (widget.onNavigateToSpec != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onNavigateToSpec,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Aller vers Spec'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final messages = project.globalChatMessages;
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }
    final sendingThis = widget.controller.isSendingGlobalQuestion;

    return Column(
      key: const ValueKey('spec-global-chat-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlobalChatHeader(
          project: project,
          hasMessages: messages.isNotEmpty,
          sending: widget.controller.isSending,
          onClear: widget.controller.clearGlobalChat,
        ),
        Expanded(
          child: messages.isEmpty && !sendingThis
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 42,
                            color: colors.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Posez une question sur la globalité du projet « ${project.name} »',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'L’Architecte Transverse a accès au lexique, au cadrage, au cahier des charges, aux objets métiers, aux règles RG-xxx et aux outils d’audit.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final q in _suggestedQuestions)
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.help_outline_rounded,
                                    size: 16,
                                  ),
                                  label: Text(q),
                                  onPressed: widget.controller.isSending
                                      ? null
                                      : () => _send(q),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length + (sendingThis ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return _GlobalStreamingBubble(
                        status: widget.controller.streamingStatus,
                        partialText: widget.controller.streamingMessage,
                        toolTraces: widget.controller.streamingToolTraces,
                        onStop: widget.controller.stopAiGeneration,
                      );
                    }
                    return _GlobalMessageBubble(
                      message: messages[index],
                      sending: widget.controller.isSending,
                      onRetry: widget.controller.retryLastGlobalQuestion,
                    );
                  },
                ),
        ),
        if (_attachmentError != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: colors.errorContainer,
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: colors.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _attachmentError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => setState(() => _attachmentError = null),
                  icon: Icon(Icons.close, color: colors.onErrorContainer),
                ),
              ],
            ),
          ),
        if (_pendingAttachments.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            color: colors.surfaceContainerLow,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, att) in _pendingAttachments.indexed)
                  Chip(
                    label: Text(att.name),
                    onDeleted: widget.controller.isSending
                        ? null
                        : () => setState(() => _pendingAttachments.removeAt(i)),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                key: const ValueKey('spec-global-chat-attach'),
                tooltip: 'Joindre un fichier (image ou texte)',
                visualDensity: VisualDensity.compact,
                onPressed: widget.controller.isSending
                    ? null
                    : _attachFromPicker,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              IconButton(
                key: const ValueKey('spec-global-chat-paste'),
                tooltip: 'Coller depuis le presse-papiers',
                visualDensity: VisualDensity.compact,
                onPressed: widget.controller.isSending
                    ? null
                    : _attachFromClipboard,
                icon: const Icon(Icons.content_paste_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Focus(
                  onKeyEvent: _handleKeyEvent,
                  skipTraversal: true,
                  child: TextField(
                    key: const ValueKey('spec-global-chat-input'),
                    controller: _inputController,
                    enabled: !widget.controller.isSending,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText:
                          'Poser une question sur l’ensemble du projet… (Entrée pour envoyer)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.controller.isSending)
                FilledButton.icon(
                  key: const ValueKey('spec-global-chat-stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  onPressed: widget.controller.stopAiGeneration,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Arrêter'),
                )
              else
                FilledButton.icon(
                  key: const ValueKey('spec-global-chat-send'),
                  onPressed: () => _send(),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Envoyer'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlobalChatHeader extends StatelessWidget {
  const _GlobalChatHeader({
    required this.project,
    required this.hasMessages,
    required this.sending,
    required this.onClear,
  });

  final SpecForgeProject project;
  final bool hasMessages;
  final bool sending;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  Icons.question_answer_rounded,
                  size: 18,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Architecte Transverse · Questions globales',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${project.lexicon.terms.length} terme(s) · '
                    '${project.cahierDesCharges.functionalRequirements.length} EXF · '
                    '${project.businessObjects.length} objet(s) · '
                    '${project.businessRules.length} RG',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (hasMessages)
            OutlinedButton.icon(
              key: const ValueKey('spec-global-chat-clear'),
              onPressed: sending ? null : onClear,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16),
              label: const Text('Effacer la discussion'),
            ),
        ],
      ),
    );
  }
}

class _GlobalMessageBubble extends StatelessWidget {
  const _GlobalMessageBubble({
    required this.message,
    required this.sending,
    required this.onRetry,
  });

  final SpecChatMessage message;
  final bool sending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? colors.primaryContainer
                : (message.failedResponse != null
                      ? colors.errorContainer
                      : colors.surfaceContainerHighest),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.attachments.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in message.attachments)
                      Chip(
                        avatar: Icon(
                          a.isImage
                              ? Icons.image_outlined
                              : Icons.description_outlined,
                          size: 14,
                        ),
                        label: Text(a.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              if (!isUser && message.toolTraces.isNotEmpty) ...[
                _GlobalToolTracesBar(traces: message.toolTraces),
                const SizedBox(height: 8),
              ],
              SelectableText(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isUser ? colors.onPrimaryContainer : colors.onSurface,
                ),
              ),
              if (!isUser &&
                  (message.failedResponse != null ||
                      message.text.startsWith('Erreur lors de l’analyse'))) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: ValueKey('spec-global-chat-retry-${message.id}'),
                    onPressed: sending ? null : onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Réessayer'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalStreamingBubble extends StatelessWidget {
  const _GlobalStreamingBubble({
    required this.status,
    required this.partialText,
    required this.toolTraces,
    required this.onStop,
  });

  final String status;
  final String? partialText;
  final List<VibeToolTrace> toolTraces;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (toolTraces.isNotEmpty) ...[
              _GlobalToolTracesBar(traces: toolTraces),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.isEmpty ? 'Analyse en cours…' : status,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const ValueKey('spec-global-chat-stop-streaming'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.error,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Arrêter'),
                ),
              ],
            ),
            if (partialText != null && partialText!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(partialText!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlobalToolTracesBar extends StatefulWidget {
  const _GlobalToolTracesBar({required this.traces});

  final List<VibeToolTrace> traces;

  @override
  State<_GlobalToolTracesBar> createState() => _GlobalToolTracesBarState();
}

class _GlobalToolTracesBarState extends State<_GlobalToolTracesBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = widget.traces.length;
    final hasError = widget.traces.any((t) => t.isError);
    final label = count == 1
        ? '1 outil consulté : ${widget.traces.single.name}'
        : '$count outils consultés';

    return Container(
      key: const ValueKey('spec-global-chat-tools'),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasError
                        ? Icons.warning_amber_rounded
                        : Icons.troubleshoot_outlined,
                    size: 14,
                    color: hasError ? colors.error : colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in widget.traces)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '• ${t.name}${t.summary.isEmpty ? '' : ' — ${t.summary}'}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
