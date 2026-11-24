/// Panneau de chat IA spécialisé pour l'étape active du wizard UX ([UxStageAiChatPane]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/ux/ux_forge_stage.dart';
import '../services/spec_forge_controller.dart';
import 'spec_chat_widgets.dart';

/// Préfixe des clés de widgets du chat des étapes du wizard UX.
const String uxChatKeyPrefix = 'ux-chat';

/// Affiche le dialogue spécialisé de l'étape UX active, les cartes `VibeAskUserCard`,
/// les pièces jointes / presse-papiers et les contrôles d'avancement du wizard UX.
class UxStageAiChatPane extends StatefulWidget {
  /// Crée le panneau de chat UX connecté au [controller].
  const UxStageAiChatPane({
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

  /// Proportion courante de la zone de chat (utilisée pour l'icône de réduction).
  final double? chatWidthFraction;

  /// Callback appelé au clic sur l'icône cyclique de réduction (0 % / 30 % / 50 %).
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
  State<UxStageAiChatPane> createState() => _UxStageAiChatPaneState();
}

class _UxStageAiChatPaneState extends State<UxStageAiChatPane> {
  final _scrollController = ScrollController();
  UxForgeStage? _lastStage;
  int _lastMessageCount = 0;

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.project;
    if (project == null) return const SizedBox.shrink();

    final stage = project.uxSpec.currentStage;
    final stageState = project.uxSpec.stageStateFor(stage);
    final messages = stageState.messages;
    if (_lastStage != stage || messages.length != _lastMessageCount) {
      _lastStage = stage;
      _lastMessageCount = messages.length;
      _scrollToBottom();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isSendingThisStage =
        widget.controller.isSendingUx &&
        widget.controller.sendingUxStage == stage;

    return Column(
      key: const ValueKey('ux-stage-ai-chat-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UxAgentHeader(
          stage: stage,
          stageState: stageState,
          isSending: widget.controller.isSending,
          chatWidthFraction: widget.chatWidthFraction,
          onCycleChatSize: widget.onCycleChatSize,
          onClearChat: widget.controller.clearUxStageChat,
          onAskMore: () => widget.controller.sendUxUserMessage(
            '',
            requestsMoreQuestions: true,
          ),
          onAdvanceStage: stage.next == null
              ? null
              : () => widget.controller.goToUxStage(
                  stage.next!,
                  validateCurrent: true,
                ),
        ),
        Expanded(
          child: messages.isEmpty && !isSendingThisStage
              ? _EmptyUxStageChatPlaceholder(
                  stage: stage,
                  isSending: widget.controller.isSending,
                  onStart: () => widget.controller.kickoffUxStageIfEmpty(stage),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: messages.length + (isSendingThisStage ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return SpecStreamingBubble(
                        keyPrefix: uxChatKeyPrefix,
                        agentTitle: stage.agentTitle,
                        status: widget.controller.streamingStatus,
                        partialText: widget.controller.streamingMessage,
                        toolTraces: widget.controller.streamingToolTraces,
                        onStop: widget.controller.stopAiGeneration,
                      );
                    }
                    final msg = messages[index];
                    return SpecChatMessageTile(
                      keyPrefix: uxChatKeyPrefix,
                      message: msg,
                      sending: widget.controller.isSending,
                      onSubmitAskUser: (answers) => widget.controller
                          .submitUxAskUserAnswers(msg.id, answers),
                      onAskMore: (answers) =>
                          widget.controller.submitUxAskUserAnswers(
                            msg.id,
                            answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () =>
                          widget.controller.skipUxAskUser(msg.id),
                      onRetry: () => widget.controller.retryLastFailedUxTurn(),
                    );
                  },
                ),
        ),
        if (stageState.readyToAdvance && stage.next != null)
          Container(
            color: colors.tertiaryContainer.withValues(alpha: 0.45),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${stage.agentTitle} indique que cette étape UX est prête pour la suivante.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onTertiaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('ux-stage-ready-advance-btn'),
                  onPressed: widget.controller.isSending
                      ? null
                      : () => widget.controller.goToUxStage(
                          stage.next!,
                          validateCurrent: true,
                        ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(
                    'Passer à : ${stage.next!.shortLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        SpecChatComposer(
          keyPrefix: uxChatKeyPrefix,
          sending: widget.controller.isSending,
          hintText:
              'Répondre, joindre ou coller (Ctrl+V) pour ${stage.agentTitle}…',
          onSend: (text, attachments) => widget.controller.sendUxUserMessage(
            text,
            attachments: attachments,
          ),
          onStop: widget.controller.stopAiGeneration,
          pickAttachments: widget.pickAttachments,
          pasteAttachments: widget.pasteAttachments,
          hasClipboardMedia: widget.hasClipboardMedia,
          pasteClipboardMedia: widget.pasteClipboardMedia,
        ),
      ],
    );
  }
}

class _UxAgentHeader extends StatelessWidget {
  const _UxAgentHeader({
    required this.stage,
    required this.stageState,
    required this.isSending,
    required this.chatWidthFraction,
    required this.onCycleChatSize,
    required this.onClearChat,
    required this.onAskMore,
    required this.onAdvanceStage,
  });

  final UxForgeStage stage;
  final UxStageState stageState;
  final bool isSending;
  final double? chatWidthFraction;
  final VoidCallback? onCycleChatSize;
  final VoidCallback onClearChat;
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
                      '${stage.agentTitle} · Étape UX ${stage.stepNumber}/${UxForgeStage.values.length}',
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
              if (stageState.messages.isNotEmpty)
                IconButton(
                  key: const ValueKey('ux-chat-clear-btn'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Effacer la conversation',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  onPressed: isSending ? null : onClearChat,
                ),
              if (onCycleChatSize != null)
                IconButton(
                  key: const ValueKey('ux-chat-cycle-size-btn'),
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
                    key: const ValueKey('ux-stage-ask-more-btn'),
                    onPressed: isSending ? null : onAskMore,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.quiz_outlined, size: 15),
                    label: const Text('+ Questions'),
                  ),
                if (onAdvanceStage != null)
                  FilledButton.tonalIcon(
                    key: const ValueKey('ux-stage-validate-next-btn'),
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

class _EmptyUxStageChatPlaceholder extends StatelessWidget {
  const _EmptyUxStageChatPlaceholder({
    required this.stage,
    required this.isSending,
    required this.onStart,
  });

  final UxForgeStage stage;
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
              key: const ValueKey('ux-stage-kickoff-btn'),
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
