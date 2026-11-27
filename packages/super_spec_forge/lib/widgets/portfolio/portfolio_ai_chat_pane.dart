/// Volet de conversation IA dédié au découpage d'un projet en Initiatives et Features ([PortfolioAiChatPane]).
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../services/spec_forge_controller.dart';
import '../spec_ai_context_dialog.dart';
import '../spec_chat_widgets.dart';

/// Préfixe des clés de widgets du chat IA de portefeuille.
const String portfolioChatKeyPrefix = 'portfolio-chat';

/// Volet latéral de l'agent IA « Product Portfolio & Feature Slicing Architect ».
class PortfolioAiChatPane extends StatefulWidget {
  /// Crée le volet connecté au [controller].
  const PortfolioAiChatPane({
    required this.controller,
    required this.onCollapse,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal de `super_spec_forge`.
  final SpecForgeController controller;

  /// Callback de repli du panneau de chat.
  final VoidCallback onCollapse;

  /// Sélecteur optionnel de pièces jointes.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant la présence d'un média dans le presse-papiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers sur `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<PortfolioAiChatPane> createState() => _PortfolioAiChatPaneState();
}

class _PortfolioAiChatPaneState extends State<PortfolioAiChatPane> {
  final ScrollController _scrollController = ScrollController();
  int _lastRenderedMessageCount = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomSoon() {
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

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final messages = project.portfolioChatMessages;
    final sending = widget.controller.isSending;
    final sendingPortfolio = widget.controller.isSendingPortfolio;

    if (messages.length != _lastRenderedMessageCount || sendingPortfolio) {
      _lastRenderedMessageCount = messages.length;
      _scrollToBottomSoon();
    }

    return Container(
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Découpage Produit IA',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Initiatives stratégiques & Vertical Slices',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message:
                          'Poser des questions d’arbitrage sur le MVP et les lots',
                      child: IconButton(
                        key: const ValueKey('$portfolioChatKeyPrefix-ask-more'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: sending
                            ? null
                            : () => widget.controller.sendPortfolioMessage(
                                '',
                                requestsMoreQuestions: true,
                              ),
                        icon: const Icon(Icons.quiz_outlined),
                      ),
                    ),
                    if (messages.isNotEmpty)
                      Tooltip(
                        message: 'Effacer l’historique de ce chat',
                        child: IconButton(
                          key: const ValueKey('$portfolioChatKeyPrefix-clear'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: sending
                              ? null
                              : widget.controller.clearPortfolioChat,
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                      ),
                    Tooltip(
                      message: 'Replier le chat IA',
                      child: IconButton(
                        key: const ValueKey('$portfolioChatKeyPrefix-collapse'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: widget.onCollapse,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
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
                      keyPrefix: portfolioChatKeyPrefix,
                      onPressed: () {
                        final inspection = widget.controller
                            .inspectPortfolioAiContext();
                        if (inspection != null) {
                          showSpecAiContextDialog(
                            context,
                            inspection: inspection,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty && !sendingPortfolio
                ? _buildEmptyState(context, theme, colors, sending)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: messages.length + (sendingPortfolio ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= messages.length) {
                        return SpecStreamingBubble(
                          keyPrefix: portfolioChatKeyPrefix,
                          agentTitle: 'Architecte Portefeuille',
                          status: widget.controller.streamingStatus,
                          partialText: widget.controller.streamingMessage,
                          toolTraces: widget.controller.streamingToolTraces,
                          onStop: widget.controller.stopAiGeneration,
                        );
                      }
                      final msg = messages[index];
                      return SpecChatMessageTile(
                        keyPrefix: portfolioChatKeyPrefix,
                        message: msg,
                        sending: sending,
                        onSubmitAskUser: (answers) => widget.controller
                            .submitPortfolioAskUserAnswers(msg.id, answers),
                        onAskMore: (answers) async {
                          await widget.controller.submitPortfolioAskUserAnswers(
                            msg.id,
                            answers,
                          );
                          if (!widget.controller.isSending) {
                            await widget.controller.sendPortfolioMessage(
                              '',
                              requestsMoreQuestions: true,
                            );
                          }
                        },
                        onSkipAskUser: () =>
                            widget.controller.skipPortfolioAskUser(msg.id),
                        onRetry: widget.controller.retryLastPortfolioTurn,
                      );
                    },
                  ),
          ),
          SpecChatComposer(
            keyPrefix: portfolioChatKeyPrefix,
            sending: sending,
            hintText:
                'Décrivez les lots souhaités, ajoutez une initiative ou demandez un découpage…',
            onSend: (text, attachments) => widget.controller
                .sendPortfolioMessage(text, attachments: attachments),
            onStop: widget.controller.stopAiGeneration,
            pickAttachments: widget.pickAttachments,
            pasteAttachments: widget.pasteAttachments,
            hasClipboardMedia: widget.hasClipboardMedia,
            pasteClipboardMedia: widget.pasteClipboardMedia,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
    bool sending,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Découper le projet en Initiatives & Features',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'L’assistant analyse l’idée du projet pour proposer des initiatives cohérentes et des features verticales prêtes à être ouvertes dans les 4 Wizards.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('$portfolioChatKeyPrefix-kickoff-btn'),
                  onPressed: sending
                      ? null
                      : () => widget.controller.sendPortfolioMessage(
                          'Analyse l’idée du projet et propose un découpage structuré en Initiatives (INIT-xx) et Features fonctionnelles verticales (FEAT-xx) avec priorités MoSCoW et lot MVP.',
                        ),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('Proposer le découpage initial'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.flag_outlined, size: 15),
                label: const Text('Distinguer MVP vs Lot 2'),
                onPressed: sending
                    ? null
                    : () => widget.controller.sendPortfolioMessage(
                        'Organise les features entre un socle MVP indispensable (Must) et des lots ultérieurs (Should / Could).',
                      ),
              ),
              ActionChip(
                avatar: const Icon(Icons.call_split_rounded, size: 15),
                label: const Text('Affiner les features trop larges'),
                onPressed: sending
                    ? null
                    : () => widget.controller.sendPortfolioMessage(
                        'Identifie les features trop volumineuses et découpe-les en tranches verticales autonomes.',
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
