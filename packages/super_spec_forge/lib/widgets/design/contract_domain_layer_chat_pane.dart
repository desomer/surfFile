/// Volet de chat IA dédié à la couche Domain (Architecture Hexagonale)
/// d'un objet métier côté Design ([ContractDomainLayerChatPane]).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/domain_layer_spec.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_ai_context_dialog.dart';
import '../spec_chat_widgets.dart';

/// Conversation unifiée avec l'agent Architecte Couche Domain pour remplir et
/// affiner les 7 onglets (`Invariants`, `State changing`, `Query`,
/// `Policy Services`, `Factory`, `Domain events`, `Persistence policy`).
class ContractDomainLayerChatPane extends StatefulWidget {
  /// Crée le volet de chat pour [entryId] dans [domainId].
  const ContractDomainLayerChatPane({
    required this.controller,
    required this.domainId,
    required this.entryId,
    required this.modelName,
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

  /// Identifiant du domaine parent.
  final String domainId;

  /// Identifiant de l'entrée du modèle.
  final String entryId;

  /// Nom affiché du modèle.
  final String modelName;

  /// Onglet actuellement affiché à droite pour contextualiser les suggestions.
  final DomainLayerTab activeTab;

  /// Callback repliant le volet de chat sur son rail latéral.
  final VoidCallback onCollapse;

  /// Sélecteurs injectables de pièces jointes et presse-papiers (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<ContractDomainLayerChatPane> createState() =>
      _ContractDomainLayerChatPaneState();
}

class _ContractDomainLayerChatPaneState
    extends State<ContractDomainLayerChatPane> {
  static const String _keyPrefix = 'domain-layer-chat';

  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  SpecForgeController get _controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _quickPromptsFor(DomainLayerTab tab) => <String>[
    'Génère toute la couche Domain (invariants, commandes, queries, factory, events et repository).',
    'Propose les éléments pertinents pour l’onglet ${tab.label}.',
    'Vérifie la cohérence entre State changing, Invariants et Domain events.',
  ];

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
      _controller.sendDomainLayerMessage(
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
    final messages = _controller.domainLayerChat(
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
    final sendingThis = _controller.isSendingDomainLayer(
      widget.domainId,
      widget.entryId,
    );
    final prompts = _quickPromptsFor(widget.activeTab);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                spacing: 8,
                children: [
                  Icon(Icons.hexagon_outlined, size: 18, color: colors.primary),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Architecte Domain · ${widget.modelName}',
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
                  if (messages.isNotEmpty)
                    IconButton(
                      key: const ValueKey('$_keyPrefix-clear'),
                      tooltip: 'Effacer la conversation',
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      onPressed: busy
                          ? null
                          : () => _controller.clearDomainLayerChat(
                              widget.domainId,
                              widget.entryId,
                            ),
                    ),
                  IconButton(
                    key: const ValueKey('$_keyPrefix-collapse'),
                    tooltip: 'Masquer le chat IA',
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    onPressed: widget.onCollapse,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SpecChatContextButton(
                    keyPrefix: _keyPrefix,
                    onPressed: () {
                      final inspection = _controller
                          .inspectDomainLayerAiContext(
                            widget.domainId,
                            widget.entryId,
                          );
                      if (inspection != null) {
                        showSpecAiContextDialog(
                          context,
                          inspection: inspection,
                        );
                      }
                    },
                  ),
                  if (messages.isNotEmpty)
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
                ],
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
                        'Décrivez les règles métier, comportements, calculs, '
                        'événements ou contrats Repository de « ${widget.modelName} » : '
                        'l’assistant remplit les 7 onglets de la couche Domain.',
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
                        agentTitle: 'Architecte Domain · ${widget.modelName}',
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
                          _controller.submitDomainLayerAskUserAnswers(
                            widget.domainId,
                            widget.entryId,
                            message.id,
                            answers,
                          ),
                      onAskMore: (answers) =>
                          _controller.submitDomainLayerAskUserAnswers(
                            widget.domainId,
                            widget.entryId,
                            message.id,
                            answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () => _controller.skipDomainLayerAskUser(
                        widget.domainId,
                        widget.entryId,
                        message.id,
                      ),
                      onRetry: () => _controller.retryLastDomainLayerTurn(
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
          hintText:
              'Concevoir la couche Domain de ${widget.modelName} (${widget.activeTab.label})…',
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
