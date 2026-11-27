/// Volet de chat IA dédié à la page Design « Systèmes & Services »
/// ([SystemsServicesChatPane]).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/domain_catalog.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_chat_widgets.dart';

/// Conversation unifiée avec l'Architecte Urbaniste SI pour recenser et
/// structurer les applications externes (`EXT-*`), fronts Web/Mobile, BFF,
/// microservices et applications monolithiques du domaine en cours.
class SystemsServicesChatPane extends StatefulWidget {
  /// Crée le volet de chat pour [domain].
  const SystemsServicesChatPane({
    required this.controller,
    required this.domain,
    required this.activeFilterKind,
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

  /// Catégorie actuellement filtrée à droite (`null` = toutes).
  final DomainSystemKind? activeFilterKind;

  /// Callback repliant le volet de chat sur son rail latéral.
  final VoidCallback onCollapse;

  /// Sélecteurs injectables de pièces jointes et presse-papiers (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<SystemsServicesChatPane> createState() =>
      _SystemsServicesChatPaneState();
}

class _SystemsServicesChatPaneState extends State<SystemsServicesChatPane> {
  static const String _keyPrefix = 'systems-services-chat';

  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  SpecForgeController get _controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _quickPrompts() {
    final hasProject = _controller.project != null;
    final sourceHint = hasProject
        ? 'du projet « ${_controller.project!.name} » et du domaine « ${widget.domain.name} »'
        : 'du domaine « ${widget.domain.name} »';
    return <String>[
      'Cartographie les applications externes, Tools openSource, fronts (Web / Mobile), BFF et services/monolithe à partir $sourceHint.',
      'Identifie les applications externes (PSP, email/SMS, ERP) et Tools openSource (Keycloak, Kafka, MinIO…) pour préparer les post-its EXT-* de l’Event Storming.',
      'Propose un découpage réaliste entre Fronts, BFF éventuel, Tools openSource et (Micro)Services ou Monolithe modulaire pour « ${widget.domain.name} ».',
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
      _controller.sendSystemsServicesMessage(
        widget.domain.id,
        text,
        attachments: attachments,
        requestsMoreQuestions: requestsMoreQuestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _controller.systemsServicesChat(widget.domain.id);
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _controller.isSending;
    final sendingThis = _controller.isSendingSystemsServices(widget.domain.id);
    final prompts = _quickPrompts();
    final focusLabel =
        widget.activeFilterKind?.label ?? 'Toutes les catégories';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.apps_rounded, size: 18, color: colors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Architecte Urbaniste · ${widget.domain.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Focus : $focusLabel',
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
                      : () => _controller.clearSystemsServicesChat(
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
                        'Décrivez votre paysage applicatif ou utilisez une suggestion ci-dessous pour '
                        'définir les applications externes et Tools openSource (utilisables en `EXT-*` '
                        'dans l’Event Storming), les fronts Web/Mobile, les BFF, les microservices '
                        'et les applications monolithiques du domaine « ${widget.domain.name} ».',
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
                        agentTitle:
                            'Architecte Urbaniste · ${widget.domain.name}',
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
                          _controller.submitSystemsServicesAskUserAnswers(
                            widget.domain.id,
                            message.id,
                            answers,
                          ),
                      onAskMore: (answers) =>
                          _controller.submitSystemsServicesAskUserAnswers(
                            widget.domain.id,
                            message.id,
                            answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () =>
                          _controller.skipSystemsServicesAskUser(
                            widget.domain.id,
                            message.id,
                          ),
                      onRetry: () =>
                          _controller.retryLastSystemsServicesTurn(
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
              'Définir les systèmes & services de ${widget.domain.name} ($focusLabel)…',
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
