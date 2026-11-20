/// Panneau de chat IA spécialisé pour l'étape active du wizard ([StageAiChatPane]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_forge_stage.dart';
import '../models/spec_stage_chat.dart';
import '../services/spec_forge_controller.dart';

/// Affiche le dialogue spécialisé de l'étape active, les cartes `VibeAskUserCard`
/// et les contrôles d'avancement du wizard.
class StageAiChatPane extends StatefulWidget {
  /// Crée le panneau de chat connecté au [controller].
  const StageAiChatPane({required this.controller, super.key});

  /// Contrôleur principal.
  final SpecForgeController controller;

  @override
  State<StageAiChatPane> createState() => _StageAiChatPaneState();
}

class _StageAiChatPaneState extends State<StageAiChatPane> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
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

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty || widget.controller.isSending) return;
    _inputController.clear();
    widget.controller.sendUserMessage(text);
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
          onStartOrContinue: () =>
              widget.controller.kickoffStageIfEmpty(stage),
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
        _ChatInputBar(
          controller: _inputController,
          stage: stage,
          sending: widget.controller.isSending,
          onSend: _send,
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
    required this.onStartOrContinue,
    required this.onAskMore,
    required this.onAdvanceStage,
  });

  final SpecForgeStage stage;
  final SpecStageState stageState;
  final bool isSending;
  final VoidCallback onStartOrContinue;
  final VoidCallback onAskMore;
  final VoidCallback? onAdvanceStage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                      '${stage.agentTitle} · Étape ${stage.stepNumber}/5',
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
    required this.onStart,
  });

  final SpecForgeStage stage;
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Lancer l’entretien IA de cette étape'),
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
  });

  final SpecChatMessage message;
  final bool sending;
  final ValueChanged<Map<String, Object?>> onSubmitAskUser;
  final ValueChanged<Map<String, Object?>> onAskMore;
  final VoidCallback onSkipAskUser;

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

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.agentTitle,
    required this.status,
    required this.partialText,
  });

  final String agentTitle;
  final String status;
  final String? partialText;

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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  status.isEmpty ? '$agentTitle réfléchit…' : status,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
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

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.stage,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final SpecForgeStage stage;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  onSend();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: controller,
                enabled: !sending,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Répondre ou préciser à ${stage.agentTitle}… (Entrée pour envoyer)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}
