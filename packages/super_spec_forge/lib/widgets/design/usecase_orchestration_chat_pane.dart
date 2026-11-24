/// Volet de chat IA dédié à la page Design « Cas d’usage & orchestration »
/// ([UseCaseOrchestrationChatPane]).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/domain_catalog.dart';
import '../../models/usecase_orchestration_spec.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_chat_widgets.dart';

/// Conversation unifiée avec l'Architecte Couche Applicative (DDD, CQRS, Saga)
/// pour remplir et affiner les 3 onglets (`Cartographie`, `Use Cases`,
/// `Sagas & Compensations`) à partir du projet actif et du domaine en cours.
class UseCaseOrchestrationChatPane extends StatefulWidget {
  /// Crée le volet de chat pour [domain].
  const UseCaseOrchestrationChatPane({
    required this.controller,
    required this.domain,
    required this.activeTab,
    required this.onCollapse,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Domaine fonctionnel actuellement sélectionné.
  final FunctionalDomain domain;

  /// Onglet actuellement consulté à droite pour contextualiser les suggestions.
  final UseCaseOrchestrationTab activeTab;

  /// Callback repliant le volet de chat sur son rail latéral.
  final VoidCallback onCollapse;

  /// Sélecteurs injectables de pièces jointes et presse-papiers (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<UseCaseOrchestrationChatPane> createState() =>
      _UseCaseOrchestrationChatPaneState();
}

class _UseCaseOrchestrationChatPaneState
    extends State<UseCaseOrchestrationChatPane> {
  static const String _keyPrefix = 'usecase-orchestration-chat';

  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  SpecForgeController get _controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _quickPromptsFor(UseCaseOrchestrationTab tab) {
    final hasProject = _controller.project != null;
    final sourceHint = hasProject
        ? 'du projet « ${_controller.project!.name} » et des contrats du domaine'
        : 'des contrats du domaine « ${widget.domain.name} »';
    return <String>[
      'Génère la cartographie par Bounded Context, les Use Cases CQRS détaillés (10 sections) et les Sagas à partir $sourceHint.',
      'Complète ou affine l’onglet « ${tab.label} » pour le domaine « ${widget.domain.name} ».',
      'Conçois les Sagas en Mermaid et leur matrice complète de compensations (Rollback, Criticité, Idempotence, Retry, Timeout).',
    ];
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _send(
    String text, {
    List<VibeChatAttachment> attachments = const <VibeChatAttachment>[],
    bool requestsMoreQuestions = false,
  }) {
    if (_controller.isSending) return;
    unawaited(
      _controller.sendUseCaseOrchestrationMessage(
        widget.domain.id,
        text,
        attachments: attachments,
        requestsMoreQuestions: requestsMoreQuestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _controller.useCaseOrchestrationChat(widget.domain.id);
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _controller.isSending;
    final sendingThis = _controller.isSendingUseCaseOrchestration(
      widget.domain.id,
    );
    final prompts = _quickPromptsFor(widget.activeTab);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            spacing: 8,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: colors.primary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Architecte Use Cases · ${widget.domain.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Focus : ${widget.activeTab.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (messages.isNotEmpty) ...[
                OutlinedButton.icon(
                  key: const ValueKey('$_keyPrefix-ask-more'),
                  onPressed: busy
                      ? null
                      : () => _send('', requestsMoreQuestions: true),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.quiz_outlined, size: 15),
                  label: const Text('+ Questions'),
                ),
                IconButton(
                  key: const ValueKey('$_keyPrefix-clear'),
                  tooltip: 'Effacer la conversation',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  onPressed: busy
                      ? null
                      : () => _controller.clearUseCaseOrchestrationChat(
                          widget.domain.id,
                        ),
                ),
              ],
              IconButton(
                key: const ValueKey('$_keyPrefix-collapse'),
                tooltip: 'Masquer le chat IA',
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                onPressed: widget.onCollapse,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: messages.isEmpty && !sendingThis
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Text(
                        'Décrivez un besoin ou utilisez les actions ci-dessous pour '
                        'cartographier les Use Cases CQRS et les Sagas du domaine '
                        '« ${widget.domain.name} » à partir des fichiers du projet en cours.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (i, prompt) in prompts.indexed)
                            ActionChip(
                              key: ValueKey('$_keyPrefix-quick-$i'),
                              label: Text(prompt),
                              onPressed: busy ? null : () => _send(prompt),
                            ),
                        ],
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length + (sendingThis ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return SpecStreamingBubble(
                        keyPrefix: _keyPrefix,
                        agentTitle: 'Architecte Use Cases · ${widget.domain.name}',
                        status: _controller.streamingStatus,
                        partialText: _controller.streamingMessage,
                        toolTraces: _controller.streamingToolTraces,
                        onStop: _controller.stopAiGeneration,
                      );
                    }
                    final message = messages[index];
                    return SpecChatMessageTile(
                      keyPrefix: _keyPrefix,
                      message: message,
                      sending: busy,
                      onSubmitAskUser: (answers) =>
                          _controller.submitUseCaseOrchestrationAskUserAnswers(
                            widget.domain.id,
                            message.id,
                            answers,
                          ),
                      onAskMore: (answers) =>
                          _controller.submitUseCaseOrchestrationAskUserAnswers(
                            widget.domain.id,
                            message.id,
                            answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () =>
                          _controller.skipUseCaseOrchestrationAskUser(
                            widget.domain.id,
                            message.id,
                          ),
                      onRetry: () =>
                          _controller.retryLastUseCaseOrchestrationTurn(
                            widget.domain.id,
                          ),
                    );
                  },
                ),
        ),
        SpecChatComposer(
          keyPrefix: _keyPrefix,
          sending: busy,
          hintText:
              'Concevoir Use Cases & Sagas de ${widget.domain.name} (${widget.activeTab.label})…',
          onSend: (text, attachments) => _send(text, attachments: attachments),
          onStop: _controller.stopAiGeneration,
          pickAttachments: widget.pickAttachments,
          pasteAttachments: widget.pasteAttachments,
          hasClipboardMedia: widget.hasClipboardMedia,
          pasteClipboardMedia: widget.pasteClipboardMedia,
        ),
      ],
    );
  }
}
