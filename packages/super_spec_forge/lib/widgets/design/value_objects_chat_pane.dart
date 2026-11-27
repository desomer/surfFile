/// Volet de chat IA dédié au Catalogue des Value Objects en Architecture
/// Hexagonale ([ValueObjectsChatPane]).
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../../models/domain_catalog.dart';
import '../../models/value_object_spec.dart';
import '../../services/spec_forge_controller.dart';
import '../spec_chat_widgets.dart';

/// Conversation IA avec l'Architecte Value Objects (DDD / Hexagonal),
/// ciblant soit le Shared Kernel du workspace, soit un domaine précis.
class ValueObjectsChatPane extends StatefulWidget {
  /// Crée le volet de chat pour [scope] (et [domain] si porté par un domaine).
  const ValueObjectsChatPane({
    required this.controller,
    required this.scope,
    this.domain,
    required this.onCollapse,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Contrôleur principal.
  final SpecForgeController controller;

  /// Portée active (`shared` ou `domain`).
  final ValueObjectScope scope;

  /// Domaine sélectionné lorsque [scope] vaut [ValueObjectScope.domain].
  final FunctionalDomain? domain;

  /// Callback repliant le volet sur son rail latéral.
  final VoidCallback onCollapse;

  /// Sélecteurs injectables de pièces jointes et presse-papiers (tests).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;
  final bool Function()? hasClipboardMedia;
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<ValueObjectsChatPane> createState() => _ValueObjectsChatPaneState();
}

class _ValueObjectsChatPaneState extends State<ValueObjectsChatPane> {
  static const String _keyPrefix = 'value-objects-chat';

  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  SpecForgeController get _controller => widget.controller;
  String? get _domainId =>
      widget.scope == ValueObjectScope.domain ? widget.domain?.id : null;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<String> _quickPrompts() {
    if (widget.scope == ValueObjectScope.shared) {
      return const <String>[
        'Propose les Value Objects fondamentaux du Shared Kernel (contact, finance, identité, temps) avec exemples valides et invalides.',
        'Enrichis les Value Objects existants du Shared Kernel avec leurs règles de normalisation et contre-exemples TDD.',
        'Crée les Value Objects composites Money, DateRange et PostalAddress avec règles inter-champs strictes.',
      ];
    }
    final domainName = widget.domain?.name ?? 'ce domaine';
    return <String>[
      'Analyse les modèles du domaine « $domainName » pour détecter la Primitive Obsession et propose les Value Objects manquants.',
      'Conçois les Value Objects métier clés du domaine « $domainName » (scalaires et composites) sans dupliquer le Shared Kernel.',
      'Complète les exemples valides et contre-exemples invalides TDD de tous les Value Objects du domaine « $domainName ».',
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
      _controller.sendValueObjectsMessage(
        scope: widget.scope,
        domainId: _domainId,
        text: text,
        attachments: attachments,
        requestsMoreQuestions: requestsMoreQuestions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _controller.valueObjectsChat(
      scope: widget.scope,
      domainId: _domainId,
    );
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _scrollToBottom();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _controller.isSending;
    final sendingThis = _controller.isSendingValueObjects(
      scope: widget.scope,
      domainId: _domainId,
    );
    final scopeTitle = widget.scope == ValueObjectScope.shared
        ? 'Shared Kernel'
        : (widget.domain?.name ?? 'Domaine');
    final prompts = _quickPrompts();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.diamond_outlined, size: 18, color: colors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Architecte Value Objects · $scopeTitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.scope == ValueObjectScope.shared
                          ? 'Portée Shared Kernel (workspace)'
                          : 'Portée Domaine (${widget.domain?.domainCode ?? ''})',
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
                      : () => _controller.clearValueObjectsChat(
                          scope: widget.scope,
                          domainId: _domainId,
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
                        'Décrivez les concepts métier à encapsuler en Value Objects '
                        '(scalaires ou composites) pour « $scopeTitle », ou lancez une '
                        'suggestion ci-dessous.',
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
                        agentTitle: 'Architecte Value Objects · $scopeTitle',
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
                          _controller.submitValueObjectsAskUserAnswers(
                            scope: widget.scope,
                            domainId: _domainId,
                            messageId: message.id,
                            answers: answers,
                          ),
                      onAskMore: (answers) =>
                          _controller.submitValueObjectsAskUserAnswers(
                            scope: widget.scope,
                            domainId: _domainId,
                            messageId: message.id,
                            answers: answers,
                            askMore: true,
                          ),
                      onSkipAskUser: () => _controller.skipValueObjectsAskUser(
                        scope: widget.scope,
                        domainId: _domainId,
                        messageId: message.id,
                      ),
                      onRetry: () => _controller.retryLastValueObjectsTurn(
                        scope: widget.scope,
                        domainId: _domainId,
                      ),
                    );
                  },
                ),
        ),
        SpecChatComposer(
          keyPrefix: _keyPrefix,
          sending: busy,
          hintText: 'Concevoir ou enrichir les Value Objects ($scopeTitle)…',
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
