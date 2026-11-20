/// Panneau de chat IA spécialisé pour l'étape active du wizard ([StageAiChatPane]).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import '../services/spec_forge_controller.dart';

/// Affiche le dialogue spécialisé de l'étape active, les cartes `VibeAskUserCard`,
/// les pièces jointes / presse-papiers et les contrôles d'avancement du wizard.
class StageAiChatPane extends StatefulWidget {
  /// Crée le panneau de chat connecté au [controller].
  const StageAiChatPane({
    required this.controller,
    this.chatWidthFraction,
    this.onCycleChatSize,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Proportion courante de la zone de chat (utilisée pour l’icône de réduction).
  final double? chatWidthFraction;

  /// Callback appelé au clic sur l’icône cyclique de réduction (0 % / 30 % / 50 %).
  final VoidCallback? onCycleChatSize;

  /// Sélecteur optionnel de fichiers (remplace [VibeChatAttachment.pickFiles] en test).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers (remplace [VibeChatAttachment.fromClipboard] en test).
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant si le presse-papiers contient une image ou des fichiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers lors d'un `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<StageAiChatPane> createState() => _StageAiChatPaneState();
}

class _StageAiChatPaneState extends State<StageAiChatPane> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<VibeChatAttachment> _pendingAttachments = [];
  String? _attachmentError;
  int _lastMessageCount = 0;

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
      setState(() {
        _appendPendingAttachments(picked);
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
          () => _attachmentError = 'Impossible d’importer le fichier : $error',
        );
      }
    }
  }

  Future<void> _attachFromClipboard() async {
    if (widget.controller.isSending) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucune image, fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() {
        _appendPendingAttachments(pasted);
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
              'Impossible de coller depuis le presse-papiers : $error',
        );
      }
    }
  }

  Future<void> _attachMediaFromShortcut() async {
    if (widget.controller.isSending) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteClipboardMedia ??
          (widget.hasClipboardMedia != null ? widget.pasteAttachments : null) ??
          VibeChatAttachment.fromClipboardImagesOrFiles;
      final pasted = await paster();
      if (!mounted || pasted.isEmpty) return;
      setState(() {
        _appendPendingAttachments(pasted);
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
              'Impossible de coller depuis le presse-papiers : $error',
        );
      }
    }
  }

  void _removePendingAttachment(int index) {
    if (widget.controller.isSending ||
        index < 0 ||
        index >= _pendingAttachments.length) {
      return;
    }
    setState(() {
      _pendingAttachments.removeAt(index);
      _attachmentError = null;
    });
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
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
    final isShiftInsert =
        event.logicalKey == LogicalKeyboardKey.insert &&
        keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
    if (!isCtrlOrMetaV && !isShiftInsert) return KeyEventResult.ignored;

    final hasMedia =
        (widget.hasClipboardMedia ??
            VibeChatAttachment.hasClipboardImageOrFiles)();
    if (!hasMedia) return KeyEventResult.ignored;

    unawaited(_attachMediaFromShortcut());
    return KeyEventResult.handled;
  }

  void _send() {
    if (widget.controller.isSending) return;
    final text = _inputController.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    _inputController.clear();
    setState(() {
      _pendingAttachments.clear();
      _attachmentError = null;
    });
    widget.controller.sendUserMessage(text, attachments: attachments);
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final stage = project.currentStage;
    final stageState = project.stageStateFor(stage);
    final messages = stageState.messages;
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isSendingThisStage =
        widget.controller.isSending &&
        widget.controller.sendingStage == stage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AgentHeader(
          stage: stage,
          stageState: stageState,
          isSending: widget.controller.isSending,
          chatWidthFraction: widget.chatWidthFraction,
          onCycleChatSize: widget.onCycleChatSize,
          onAskMore: () =>
              widget.controller.sendUserMessage('', requestsMoreQuestions: true),
          onAdvanceStage: stage.next == null
              ? null
              : () => widget.controller.goToStage(
                  stage.next!,
                  validateCurrent: true,
                ),
        ),
        Expanded(
          child: messages.isEmpty && !isSendingThisStage
              ? _EmptyStageChatPlaceholder(
                  stage: stage,
                  isSending: widget.controller.isSending,
                  onStart: () => widget.controller.kickoffStageIfEmpty(stage),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length + (isSendingThisStage ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return _StreamingBubble(
                        agentTitle: stage.agentTitle,
                        status: widget.controller.streamingStatus,
                        partialText: widget.controller.streamingMessage,
                        toolTraces: widget.controller.streamingToolTraces,
                        onStop: widget.controller.stopAiGeneration,
                      );
                    }
                    final msg = messages[index];
                    return _ChatMessageTile(
                      message: msg,
                      sending: widget.controller.isSending,
                      onSubmitAskUser: (answers) =>
                          widget.controller.submitAskUserAnswers(msg.id, answers),
                      onAskMore: (answers) =>
                          widget.controller.submitAskUserAnswers(
                            msg.id,
                            answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () =>
                          widget.controller.skipAskUser(msg.id),
                      onRetry: () => widget.controller.retryLastFailedTurn(),
                    );
                  },
                ),
        ),
        if (stageState.readyToAdvance && stage.next != null)
          Container(
            color: colors.tertiaryContainer.withValues(alpha: 0.45),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${stage.agentTitle} indique que cette étape est prête pour la suivante.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: widget.controller.isSending
                      ? null
                      : () => widget.controller.goToStage(
                          stage.next!,
                          validateCurrent: true,
                        ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text('Passer à : ${stage.next!.shortLabel}'),
                ),
              ],
            ),
          ),
        if (_attachmentError != null)
          Container(
            key: const ValueKey('spec-chat-attachment-error'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: colors.errorContainer,
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: colors.onErrorContainer,
                ),
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
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  onPressed: () => setState(() => _attachmentError = null),
                  icon: Icon(
                    Icons.close,
                    size: 15,
                    color: colors.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        if (_pendingAttachments.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            color: colors.surfaceContainerLow,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (index, attachment) in _pendingAttachments.indexed)
                  _PendingAttachmentChip(
                    index: index,
                    attachment: attachment,
                    onRemove: widget.controller.isSending
                        ? null
                        : () => _removePendingAttachment(index),
                  ),
              ],
            ),
          ),
        _ChatInputBar(
          controller: _inputController,
          stage: stage,
          sending: widget.controller.isSending,
          onKeyEvent: _handleInputKeyEvent,
          onAttachFromPicker: _attachFromPicker,
          onAttachFromClipboard: _attachFromClipboard,
          onSend: _send,
          onStop: widget.controller.stopAiGeneration,
        ),
      ],
    );
  }
}

class _AgentHeader extends StatelessWidget {
  const _AgentHeader({
    required this.stage,
    required this.stageState,
    required this.isSending,
    required this.chatWidthFraction,
    required this.onCycleChatSize,
    required this.onAskMore,
    required this.onAdvanceStage,
  });

  final SpecForgeStage stage;
  final SpecStageState stageState;
  final bool isSending;
  final double? chatWidthFraction;
  final VoidCallback? onCycleChatSize;
  final VoidCallback onAskMore;
  final VoidCallback? onAdvanceStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentPct = ((chatWidthFraction ?? 0.5) * 100).round();
    final isCompactPreset = (chatWidthFraction ?? 0.5) <= 0.32;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: colors.primaryContainer,
                child: Icon(
                  stage.icon,
                  size: 18,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stage.agentTitle} · Étape ${stage.stepNumber}/${SpecForgeStage.values.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      stage.agentSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onCycleChatSize != null)
                IconButton(
                  key: const ValueKey('spec-chat-cycle-size-btn'),
                  visualDensity: VisualDensity.compact,
                  tooltip: isCompactPreset
                      ? 'Masquer le chat IA ($currentPct % → 0 %)'
                      : 'Réduire le chat IA ($currentPct % → 30 %)',
                  onPressed: onCycleChatSize,
                  icon: Icon(
                    isCompactPreset
                        ? Icons.first_page_rounded
                        : Icons.chevron_left_rounded,
                  ),
                ),
            ],
          ),
          if (stageState.messages.isNotEmpty || onAdvanceStage != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (stageState.messages.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: isSending ? null : onAskMore,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.quiz_outlined, size: 15),
                    label: const Text('+ Questions'),
                  ),
                if (onAdvanceStage != null)
                  FilledButton.tonalIcon(
                    onPressed: isSending ? null : onAdvanceStage,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.navigate_next_rounded, size: 17),
                    label: const Text('Valider & Suivant'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyStageChatPlaceholder extends StatelessWidget {
  const _EmptyStageChatPlaceholder({
    required this.stage,
    required this.isSending,
    required this.onStart,
  });

  final SpecForgeStage stage;
  final bool isSending;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(stage.icon, size: 40, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              'Agent ${stage.agentTitle}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              stage.agentSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Les échanges IA restent en attente jusqu’à votre clic sur « Commencer » ou l’envoi d’un premier message.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('spec-stage-start-ai'),
              onPressed: isSending ? null : onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Commencer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageTile extends StatelessWidget {
  const _ChatMessageTile({
    required this.message,
    required this.sending,
    required this.onSubmitAskUser,
    required this.onAskMore,
    required this.onSkipAskUser,
    required this.onRetry,
  });

  final SpecChatMessage message;
  final bool sending;
  final ValueChanged<Map<String, Object?>> onSubmitAskUser;
  final ValueChanged<Map<String, Object?>> onAskMore;
  final VoidCallback onSkipAskUser;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 560),
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
                      for (final attachment in message.attachments)
                        if (attachment.isImage)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (attachment.bytes.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 200,
                                      maxHeight: 150,
                                    ),
                                    child: Image.memory(
                                      attachment.bytes,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 2),
                              Text(
                                attachment.name,
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          )
                        else
                          Chip(
                            avatar: const Icon(
                              Icons.description_outlined,
                              size: 14,
                            ),
                            label: Text(attachment.name),
                            visualDensity: VisualDensity.compact,
                          ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (!isUser && message.toolTraces.isNotEmpty) ...[
                  _ToolTracesSection(traces: message.toolTraces),
                  const SizedBox(height: 8),
                ],
                SelectableText(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUser
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
                if (message.appliedPatchSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_fix_high_rounded,
                          size: 14,
                          color: colors.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Mis à jour : ${message.appliedPatchSummary}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!isUser &&
                    (message.failedResponse != null ||
                        message.text.startsWith('Erreur lors de l’appel'))) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: ValueKey('spec-chat-retry-${message.id}'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: sending ? null : onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Réessayer / Corriger'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isUser &&
              message.askUser != null &&
              message.askUserAnswers == null &&
              !message.askUserDismissed) ...[
            const SizedBox(height: 8),
            VibeAskUserCard(
              request: message.askUser!,
              sending: sending,
              onSubmit: onSubmitAskUser,
              onAskMore: onAskMore,
              onSkip: onSkipAskUser,
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolTracesSection extends StatefulWidget {
  const _ToolTracesSection({required this.traces});

  final List<VibeToolTrace> traces;

  @override
  State<_ToolTracesSection> createState() => _ToolTracesSectionState();
}

class _ToolTracesSectionState extends State<_ToolTracesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = widget.traces.length;
    final hasError = widget.traces.any((t) => t.isError);
    final names = <String>{for (final t in widget.traces) t.name}.toList();
    final preview = names.length <= 2
        ? names.join(', ')
        : '${names.take(2).join(', ')} (+${names.length - 2})';
    final header = count == 1
        ? '1 outil utilisé : $preview'
        : '$count outils utilisés : $preview';

    return Container(
      key: const ValueKey('spec-chat-tools-section'),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? colors.error.withValues(alpha: 0.45)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('spec-chat-tools-toggle'),
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
                  Flexible(
                    child: Text(
                      header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final trace in widget.traces)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            trace.isError
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            size: 13,
                            color: trace.isError
                                ? colors.error
                                : colors.secondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              trace.summary.isEmpty
                                  ? trace.name
                                  : '${trace.name} — ${trace.summary}',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
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

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.agentTitle,
    required this.status,
    required this.partialText,
    required this.toolTraces,
    required this.onStop,
  });

  final String agentTitle;
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
        constraints: const BoxConstraints(maxWidth: 560),
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
              _ToolTracesSection(traces: toolTraces),
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
                    status.isEmpty ? '$agentTitle réfléchit…' : status,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const ValueKey('spec-chat-stop-streaming'),
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
      key: ValueKey('spec-chat-pending-attachment-$index'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment.isImage && attachment.bytes.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  attachment.bytes,
                  width: 26,
                  height: 26,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_outlined,
                    size: 18,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              )
            else
              Icon(
                attachment.isImage
                    ? Icons.image_outlined
                    : Icons.description_outlined,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
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
              key: ValueKey('spec-chat-remove-attachment-$index'),
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

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.stage,
    required this.sending,
    required this.onKeyEvent,
    required this.onAttachFromPicker,
    required this.onAttachFromClipboard,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final SpecForgeStage stage;
  final bool sending;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onAttachFromPicker;
  final VoidCallback onAttachFromClipboard;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            key: const ValueKey('spec-chat-attach'),
            tooltip: 'Joindre un fichier (image ou texte)',
            visualDensity: VisualDensity.compact,
            onPressed: sending ? null : onAttachFromPicker,
            icon: const Icon(Icons.attach_file_rounded),
          ),
          IconButton(
            key: const ValueKey('spec-chat-paste-attachment'),
            tooltip:
                'Coller une image, un fichier ou du texte du presse-papiers',
            visualDensity: VisualDensity.compact,
            onPressed: sending ? null : onAttachFromClipboard,
            icon: const Icon(Icons.content_paste_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Focus(
              onKeyEvent: onKeyEvent,
              skipTraversal: true,
              child: TextField(
                key: const ValueKey('spec-chat-input'),
                controller: controller,
                enabled: !sending,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Répondre, joindre ou coller (Ctrl+V) pour ${stage.agentTitle}…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (sending)
            FilledButton.icon(
              key: const ValueKey('spec-chat-stop'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: onStop,
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Arrêter'),
            )
          else
            FilledButton.icon(
              key: const ValueKey('spec-chat-send'),
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Envoyer'),
            ),
        ],
      ),
    );
  }
}
