/// Chat IA du détail d'un modèle ou contrat de domaine ([ContractModelChatPane]).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../services/spec_forge_controller.dart';
import '../spec_chat_widgets.dart';

/// Conversation avec l'agent qui crée et modifie les attributs d'un seul
/// modèle ; l'historique est persisté avec le modèle dans le domaine. Les
/// briques (bulles, traces d'outils, questionnaires, « + Questions », reprise,
/// pièces jointes) sont celles du chat des étapes de la spec.
class ContractModelChatPane extends StatefulWidget {
  /// Crée le chat du modèle [entryId] du domaine [domainId].
  const ContractModelChatPane({
    required this.controller,
    required this.domainId,
    required this.entryId,
    required this.modelName,
    required this.onCollapse,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  final SpecForgeController controller;
  final String domainId;
  final String entryId;

  /// Nom affiché dans l'en-tête et l'invite.
  final String modelName;
  final VoidCallback onCollapse;

  /// Remplacent les accès fichiers et presse-papiers (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<ContractModelChatPane> createState() => _ContractModelChatPaneState();
}

class _ContractModelChatPaneState extends State<ContractModelChatPane> {
  static const _keyPrefix = 'contract-chat';

  final _scroll = ScrollController();
  int _lastCount = 0;

  static const _quickPrompts = [
    'Propose les attributs essentiels de ce modèle.',
    'Ajoute les références vers les autres modèles du domaine.',
    'Vérifie les types, champs obligatoires et énumérations.',
  ];

  SpecForgeController get _controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
      _controller.sendDomainModelMessage(
        widget.domainId,
        widget.entryId,
        text,
        attachments: attachments,
        requestsMoreQuestions: requestsMoreQuestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _controller.domainModelChat(
      widget.domainId,
      widget.entryId,
    );
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _controller.isSending;
    final sendingThis = _controller.isSendingDomainModel(
      widget.domainId,
      widget.entryId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: colors.primary),
              Expanded(
                child: Text(
                  'Assistant IA · ${widget.modelName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                  tooltip: 'Effacer la conversation',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  onPressed: busy
                      ? null
                      : () => _controller.clearDomainModelChat(
                          widget.domainId,
                          widget.entryId,
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
                        'Décrivez le modèle, collez un exemple ou joignez un '
                        'document : l’assistant crée et ajuste ses attributs.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final prompt in _quickPrompts)
                            ActionChip(
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
                        agentTitle: 'Assistant ${widget.modelName}',
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
                          _controller.submitDomainModelAskUserAnswers(
                            widget.domainId,
                            widget.entryId,
                            message.id,
                            answers,
                          ),
                      onAskMore: (answers) =>
                          _controller.submitDomainModelAskUserAnswers(
                            widget.domainId,
                            widget.entryId,
                            message.id,
                            answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () => _controller.skipDomainModelAskUser(
                        widget.domainId,
                        widget.entryId,
                        message.id,
                      ),
                      onRetry: () => _controller.retryLastDomainModelTurn(
                        widget.domainId,
                        widget.entryId,
                      ),
                    );
                  },
                ),
        ),
        SpecChatComposer(
          keyPrefix: _keyPrefix,
          sending: busy,
          hintText: 'Demander à modifier ${widget.modelName}…',
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
