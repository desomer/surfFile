/// Briques de chat IA partagées par le chat des étapes de la spec
/// ([StageAiChatPane]) et celui de la fiche d'un modèle de domaine
/// ([ContractModelChatPane]) : bulles, traces d'outils, streaming et saisie.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../models/spec_stage_chat.dart';

/// Préfixe des clés de widgets du chat des étapes de la spec.
const String specChatKeyPrefix = 'spec-chat';

/// Message du chat : pièces jointes, traces d'outils, texte, résumé du patch,
/// bouton de reprise et questionnaire `VibeAskUserCard` en attente.
class SpecChatMessageTile extends StatelessWidget {
  /// Crée la bulle de [message] ; [keyPrefix] préfixe les clés de test.
  const SpecChatMessageTile({
    required this.message,
    required this.sending,
    required this.onSubmitAskUser,
    required this.onAskMore,
    required this.onSkipAskUser,
    required this.onRetry,
    this.keyPrefix = specChatKeyPrefix,
    super.key,
  });

  /// Message affiché.
  final SpecChatMessage message;

  /// Désactive les actions pendant un tour IA.
  final bool sending;

  /// Soumission des réponses du questionnaire.
  final ValueChanged<Map<String, Object?>> onSubmitAskUser;

  /// Soumission des réponses avec demande de questions complémentaires.
  final ValueChanged<Map<String, Object?>> onAskMore;

  /// Questionnaire ignoré (valeurs par défaut).
  final VoidCallback onSkipAskUser;

  /// Relance du tour en erreur.
  final VoidCallback onRetry;

  /// Préfixe des clés de widgets.
  final String keyPrefix;

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
                  SpecToolTracesSection(
                    traces: message.toolTraces,
                    keyPrefix: keyPrefix,
                  ),
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
                      key: ValueKey('$keyPrefix-retry-${message.id}'),
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

/// Section repliable listant les outils appelés par l'agent pendant un tour.
class SpecToolTracesSection extends StatefulWidget {
  /// Crée la section des [traces].
  const SpecToolTracesSection({
    required this.traces,
    this.keyPrefix = specChatKeyPrefix,
    super.key,
  });

  /// Traces des appels d'outils.
  final List<VibeToolTrace> traces;

  /// Préfixe des clés de widgets.
  final String keyPrefix;

  @override
  State<SpecToolTracesSection> createState() => _SpecToolTracesSectionState();
}

class _SpecToolTracesSectionState extends State<SpecToolTracesSection> {
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
      key: ValueKey('${widget.keyPrefix}-tools-section'),
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
            key: ValueKey('${widget.keyPrefix}-tools-toggle'),
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

/// Réponse en cours : statut, outils déjà appelés, texte partiel et arrêt.
class SpecStreamingBubble extends StatelessWidget {
  /// Crée la bulle de streaming de [agentTitle].
  const SpecStreamingBubble({
    required this.agentTitle,
    required this.status,
    required this.partialText,
    required this.toolTraces,
    required this.onStop,
    this.keyPrefix = specChatKeyPrefix,
    super.key,
  });

  /// Nom de l'agent affiché tant qu'aucun statut n'est connu.
  final String agentTitle;

  /// Statut courant du tour.
  final String status;

  /// Message partiel déjà reçu.
  final String? partialText;

  /// Outils appelés depuis le début du tour.
  final List<VibeToolTrace> toolTraces;

  /// Arrêt de la génération.
  final VoidCallback onStop;

  /// Préfixe des clés de widgets.
  final String keyPrefix;

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
              SpecToolTracesSection(traces: toolTraces, keyPrefix: keyPrefix),
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
                  key: ValueKey('$keyPrefix-stop-streaming'),
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

/// Zone de saisie du chat : erreurs d'import, pièces jointes en attente
/// (sélecteur, presse-papiers, `Ctrl+V` / `Maj+Inser`), champ et envoi/arrêt.
class SpecChatComposer extends StatefulWidget {
  /// Crée la zone de saisie ; [onSend] reçoit le texte et les pièces jointes.
  const SpecChatComposer({
    required this.sending,
    required this.hintText,
    required this.onSend,
    required this.onStop,
    this.keyPrefix = specChatKeyPrefix,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    super.key,
  });

  /// Tour IA en cours : saisie désactivée et bouton « Arrêter ».
  final bool sending;

  /// Invite du champ de saisie.
  final String hintText;

  /// Envoi du message saisi et des pièces jointes en attente.
  final void Function(String text, List<VibeChatAttachment> attachments) onSend;

  /// Arrêt de la génération en cours.
  final VoidCallback onStop;

  /// Préfixe des clés de widgets.
  final String keyPrefix;

  /// Sélecteur optionnel de fichiers (remplace [VibeChatAttachment.pickFiles] en test).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers (remplace [VibeChatAttachment.fromClipboard] en test).
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant si le presse-papiers contient une image ou des fichiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers lors d'un `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  @override
  State<SpecChatComposer> createState() => _SpecChatComposerState();
}

class _SpecChatComposerState extends State<SpecChatComposer> {
  final _inputController = TextEditingController();
  final List<VibeChatAttachment> _pendingAttachments = [];
  String? _attachmentError;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
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

  /// Importe des pièces jointes depuis [source] ; [emptyMessage] est affiché
  /// si la source ne renvoie rien (silence sinon).
  Future<void> _attachFrom(
    Future<List<VibeChatAttachment>> Function() source, {
    required String failurePrefix,
    String? emptyMessage,
  }) async {
    if (widget.sending) return;
    setState(() => _attachmentError = null);
    try {
      final attachments = await source();
      if (!mounted) return;
      if (attachments.isEmpty) {
        if (emptyMessage != null) {
          setState(() => _attachmentError = emptyMessage);
        }
        return;
      }
      setState(() {
        _appendPendingAttachments(attachments);
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
        setState(() => _attachmentError = '$failurePrefix : $error');
      }
    }
  }

  Future<void> _attachFromPicker() => _attachFrom(
    widget.pickAttachments ?? VibeChatAttachment.pickFiles,
    failurePrefix: 'Impossible d’importer le fichier',
  );

  Future<void> _attachFromClipboard() => _attachFrom(
    widget.pasteAttachments ?? VibeChatAttachment.fromClipboard,
    failurePrefix: 'Impossible de coller depuis le presse-papiers',
    emptyMessage:
        'Aucune image, fichier ou texte trouvé dans le presse-papiers.',
  );

  Future<void> _attachMediaFromShortcut() => _attachFrom(
    widget.pasteClipboardMedia ??
        (widget.hasClipboardMedia != null ? widget.pasteAttachments : null) ??
        VibeChatAttachment.fromClipboardImagesOrFiles,
    failurePrefix: 'Impossible de coller depuis le presse-papiers',
  );

  void _removePendingAttachment(int index) {
    if (widget.sending || index < 0 || index >= _pendingAttachments.length) {
      return;
    }
    setState(() {
      _pendingAttachments.removeAt(index);
      _attachmentError = null;
    });
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.sending || event is! KeyDownEvent) {
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
    if (widget.sending) return;
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
    widget.onSend(text, attachments);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final prefix = widget.keyPrefix;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_attachmentError != null)
          Container(
            key: ValueKey('$prefix-attachment-error'),
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
                    keyPrefix: prefix,
                    index: index,
                    attachment: attachment,
                    onRemove: widget.sending
                        ? null
                        : () => _removePendingAttachment(index),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                key: ValueKey('$prefix-attach'),
                tooltip: 'Joindre un fichier (image ou texte)',
                visualDensity: VisualDensity.compact,
                onPressed: widget.sending ? null : _attachFromPicker,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              IconButton(
                key: ValueKey('$prefix-paste-attachment'),
                tooltip: 'Coller une image, un fichier ou du texte du presse-papiers',
                visualDensity: VisualDensity.compact,
                onPressed: widget.sending ? null : _attachFromClipboard,
                icon: const Icon(Icons.content_paste_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Focus(
                  onKeyEvent: _handleInputKeyEvent,
                  skipTraversal: true,
                  child: TextField(
                    key: ValueKey('$prefix-input'),
                    controller: _inputController,
                    enabled: !widget.sending,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (widget.sending)
                FilledButton.icon(
                  key: ValueKey('$prefix-stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  onPressed: widget.onStop,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Arrêter'),
                )
              else
                FilledButton.icon(
                  key: ValueKey('$prefix-send'),
                  onPressed: _send,
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

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.keyPrefix,
    required this.index,
    required this.attachment,
    required this.onRemove,
  });

  final String keyPrefix;
  final int index;
  final VibeChatAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('$keyPrefix-pending-attachment-$index'),
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
              key: ValueKey('$keyPrefix-remove-attachment-$index'),
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
