/// Bulles de conversation, indicateurs de génération et pièces jointes du chat Vibe.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../../../ai/call_gemini.dart';
import '../../../ai/vibe_plan.dart';
import '../../../ai/vibe_speech_to_text.dart';
import '../../../ai/vibe_stream_parser.dart';
import 'vibe_ask_user_card.dart';
import 'vibe_chat_message.dart';
import 'vibe_plan_card.dart';

/// Puce représentant une pièce jointe en attente d'envoi.
class VibePendingAttachmentChip extends StatelessWidget {
  /// Crée une puce avec une action de retrait optionnelle.
  const VibePendingAttachmentChip({
    required this.index,
    required this.attachment,
    required this.onRemove,
    super.key,
  });

  /// Position de la pièce jointe dans la liste du chat.
  final int index;

  /// Fichier ou texte représenté par cette puce.
  final VibeChatAttachment attachment;

  /// Action de retrait, absente pendant la génération.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('vibe-chat-pending-attachment-$index'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 2, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  attachment.bytes,
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              )
            else
              Icon(
                Icons.description_outlined,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
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
              key: ValueKey('vibe-chat-remove-attachment-$index'),
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

/// Bulle de message utilisateur ou assistant, avec questionnaire éventuel.
class VibeMessageBubble extends StatelessWidget {
  /// Crée une bulle associée à [message].
  const VibeMessageBubble({
    required this.message,
    this.sending = false,
    this.isActivePlan = false,
    this.canRetryFinishedPlan = false,
    this.onSubmitAskUser,
    this.onSkipAskUser,
    this.onAskMoreAskUser,
    this.onRequestMoreQuestions,
    this.onRetryTurn,
    this.onStartPlan,
    this.onStartPlanParallel,
    this.onCancelPlan,
    this.onStopPlan,
    this.onRetryPlanLot,
    this.onRetryPlanLotPartial,
    this.onRetryPlanAll,
    this.onResumePlan,
    this.onSkipPlanLot,
    this.onTogglePlanLot,
    this.speechTranscriber,
    this.onSpeechError,
    super.key,
  });

  /// Message à afficher.
  final VibeChatMessage message;

  /// Désactive les questions pendant la génération.
  final bool sending;

  /// Indique si le plan porté par ce message est le plan interactif courant.
  final bool isActivePlan;

  /// Autorise les actions de relance sur un plan arrêté ou terminé.
  final bool canRetryFinishedPlan;

  /// Reçoit les réponses à un questionnaire.
  final ValueChanged<Map<String, Object?>>? onSubmitAskUser;

  /// Demande de répondre avec les valeurs par défaut.
  final VoidCallback? onSkipAskUser;

  /// Enregistre les réponses du questionnaire courant et demande 2 à 4 questions complémentaires.
  final ValueChanged<Map<String, Object?>>? onAskMoreAskUser;

  /// Déclenche une demande de 2 à 4 questions d'affinage sous cette réponse de l'assistant.
  final VoidCallback? onRequestMoreQuestions;

  /// Relance ce tour lorsqu'il a échoué.
  final VoidCallback? onRetryTurn;

  /// Déclenche l'exécution automatique du plan (séquentielle par défaut).
  final VoidCallback? onStartPlan;

  /// Déclenche l'exécution automatique du plan en parallèle (accessible si le mode Plan est sélectionné).
  final VoidCallback? onStartPlanParallel;

  /// Annule le plan avant démarrage.
  final VoidCallback? onCancelPlan;

  /// Arrête l'exécution du plan en cours ou en pause.
  final VoidCallback? onStopPlan;

  /// Relance le lot en échec depuis zéro (retry complet du lot).
  final VoidCallback? onRetryPlanLot;

  /// Relance le lot en échec à partir de son checkpoint partiel (retry partiel).
  final VoidCallback? onRetryPlanLotPartial;

  /// Relance l'intégralité du plan depuis le premier lot (retry complet du plan).
  final VoidCallback? onRetryPlanAll;

  /// Reprend un plan arrêté ou relance les lots ignorés.
  final VoidCallback? onResumePlan;

  /// Ignore le lot en échec et poursuit avec le suivant.
  final VoidCallback? onSkipPlanLot;

  /// Active ou désactive un lot proposé avant le lancement du plan.
  final ValueChanged<int>? onTogglePlanLot;

  /// Service optionnel de dictée vocale (Speech-to-Text) pour les champs texte du questionnaire.
  final VibeSpeechTranscriber? speechTranscriber;

  /// Callback optionnel notifié lorsqu'une erreur de dictée survient sur le questionnaire.
  final ValueChanged<String>? onSpeechError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = message.isUser
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final askUser = message.askUser;
    final plan = message.plan;
    final isResolvedAskUser =
        message.askUserAnswers != null || message.askUserDismissed;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 340.0;
        final maxBubbleWidth =
            (askUser != null && !isResolvedAskUser) || plan != null
            ? math.max(340.0, math.min(960.0, availableWidth - 16.0))
            : math.max(340.0, math.min(820.0, availableWidth * 0.80));
        return Align(
          alignment: message.isUser
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: message.isUser
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 220,
                                    maxHeight: 120,
                                  ),
                                  child: Image.memory(
                                    attachment.bytes,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      padding: const EdgeInsets.all(8),
                                      color: scheme.surface.withValues(
                                        alpha: 0.4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.image_outlined,
                                            size: 16,
                                            color: foreground,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              attachment.name,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: foreground,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                attachment.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: foreground.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 15,
                                  color: foreground,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    attachment.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: foreground,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                  if (message.text.isNotEmpty) const SizedBox(height: 6),
                ],
                if (message.toolTraces.isNotEmpty) ...[
                  VibeToolTracesSection(traces: message.toolTraces),
                  if (message.timedTraces.isNotEmpty ||
                      message.text.isNotEmpty ||
                      askUser != null ||
                      plan != null)
                    const SizedBox(height: 6),
                ],
                if (plan == null && message.timedTraces.isNotEmpty) ...[
                  VibeTimedTracesSection(
                    traces: message.timedTraces,
                    totalDurationMs: message.generationDurationMs,
                  ),
                  if (message.text.isNotEmpty || askUser != null)
                    const SizedBox(height: 6),
                ],
                if (message.text.isNotEmpty) SelectableText(message.text),
                if (askUser != null) ...[
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                  if (isResolvedAskUser)
                    VibeResolvedAskUserBadge(
                      dismissed: message.askUserDismissed,
                      usedDefaults: message.askUserUsedDefaults,
                      requestedMore: message.askUserRequestedMore,
                    )
                  else
                    VibeAskUserCard(
                      key: const ValueKey('vibe-ask-user-card'),
                      request: askUser,
                      sending: sending,
                      onSubmit: onSubmitAskUser ?? (_) {},
                      onSkip: onSkipAskUser ?? () {},
                      onAskMore: onAskMoreAskUser,
                      speechTranscriber: speechTranscriber,
                      onSpeechError: onSpeechError,
                    ),
                ],
                if (plan != null) ...[
                  if (message.text.isNotEmpty || askUser != null)
                    const SizedBox(height: 8),
                  VibePlanCard(
                    plan: plan,
                    busy: sending,
                    isActivePlan: isActivePlan,
                    canRetryFinishedPlan: canRetryFinishedPlan,
                    onStart: onStartPlan,
                    onStartParallel: onStartPlanParallel,
                    onCancel: onCancelPlan,
                    onStop: onStopPlan,
                    onRetryLot: onRetryPlanLot,
                    onRetryLotPartial: onRetryPlanLotPartial,
                    onRetryPlanAll: onRetryPlanAll,
                    onResumePlan: onResumePlan,
                    onSkipLot: onSkipPlanLot,
                    onToggleLot: onTogglePlanLot,
                  ),
                ],
                if (message.retryTurn != null && onRetryTurn != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: const ValueKey('vibe-message-retry'),
                      onPressed: sending ? null : onRetryTurn,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Réessayer'),
                    ),
                  ),
                ],
                if (onRequestMoreQuestions != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      message: 'Demander 2 à 4 questions pour affiner ou compléter cet écran',
                      child: ActionChip(
                        key: const ValueKey('vibe-message-more-questions'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: Icon(
                          Icons.add_comment_outlined,
                          size: 14,
                          color: sending
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                              : scheme.primary,
                        ),
                        label: const Text(
                          '+ de questions',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        onPressed: sending ? null : onRequestMoreQuestions,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Section compacte et dépliable présentant les outils d'introspection exécutés pour un message.
class VibeToolTracesSection extends StatefulWidget {
  /// Crée une section listant [traces].
  const VibeToolTracesSection({required this.traces, super.key});

  /// Traces d'appels d'outils associées à la réponse de l'assistant.
  final List<VibeToolTrace> traces;

  @override
  State<VibeToolTracesSection> createState() => _VibeToolTracesSectionState();
}

class _VibeToolTracesSectionState extends State<VibeToolTracesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.traces.length;
    final hasError = widget.traces.any((t) => t.isError);
    final uniqueNames = <String>{
      for (final t in widget.traces)
        if (t.name.trim().isNotEmpty) t.name,
    }.toList();
    final namesPreview = uniqueNames.length <= 2
        ? uniqueNames.join(', ')
        : '${uniqueNames.take(2).join(', ')} (+${uniqueNames.length - 2})';
    final headerLabel = count == 1
        ? '1 outil utilisé : $namesPreview'
        : '$count outils utilisés : $namesPreview';

    return Container(
      key: const ValueKey('vibe-message-tools-section'),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? scheme.error.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('vibe-message-tools-toggle'),
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
                    color: hasError ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      headerLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: scheme.onSurfaceVariant,
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
                      child: _VibeToolTraceRow(trace: trace),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VibeToolTraceRow extends StatelessWidget {
  const _VibeToolTraceRow({required this.trace});

  final VibeToolTrace trace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final argsText = trace.arguments.isEmpty ? '' : jsonEncode(trace.arguments);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            trace.isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 13,
            color: trace.isError ? scheme.error : scheme.primary,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    trace.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                    ),
                  ),
                  if (trace.isPostVerify)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'post-rendu',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  if (trace.durationMs != null)
                    Text(
                      formatVibeDuration(trace.durationMs!),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (trace.summary.isNotEmpty)
                    Text(
                      trace.summary,
                      style: TextStyle(
                        fontSize: 11,
                        color: trace.isError
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (argsText.isNotEmpty)
                Text(
                  argsText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Section compacte et dépliable présentant les traces chronométrées d'un tour IA.
class VibeTimedTracesSection extends StatefulWidget {
  /// Crée une section dépliable listant [traces].
  const VibeTimedTracesSection({
    required this.traces,
    this.totalDurationMs,
    super.key,
  });

  /// Étapes chronométrées collectées pendant la génération.
  final List<VibeTimedTrace> traces;

  /// Durée totale optionnelle affichée dans l'en-tête.
  final int? totalDurationMs;

  @override
  State<VibeTimedTracesSection> createState() => _VibeTimedTracesSectionState();
}

class _VibeTimedTracesSectionState extends State<VibeTimedTracesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = widget.traces.any((t) => t.isError);
    final total = widget.totalDurationMs;
    final header = total != null
        ? 'Traces timées (${widget.traces.length}) · ${formatVibeDuration(total)}'
        : 'Traces timées (${widget.traces.length})';
    return Container(
      key: const ValueKey('vibe-message-timed-traces'),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError
              ? scheme.error.withValues(alpha: 0.45)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('vibe-message-timed-traces-toggle'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: hasError ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: scheme.onSurfaceVariant,
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
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        trace.formatLine(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: trace.isError
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
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

/// Indique le résultat d'un questionnaire déjà traité.
class VibeResolvedAskUserBadge extends StatelessWidget {
  /// Crée une indication de questionnaire terminé ou ignoré.
  const VibeResolvedAskUserBadge({
    required this.dismissed,
    required this.usedDefaults,
    this.requestedMore = false,
    super.key,
  });

  /// Indique si l'utilisateur a ignoré les questions.
  final bool dismissed;

  /// Indique si les valeurs proposées ont été utilisées.
  final bool usedDefaults;

  /// Indique si l'utilisateur a validé les réponses en demandant « + de questions ».
  final bool requestedMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label) = dismissed
        ? (Icons.remove_circle_outline, 'Questionnaire ignoré')
        : requestedMore
        ? (
            Icons.playlist_add_check_outlined,
            'Questions complémentaires demandées',
          )
        : usedDefaults
        ? (Icons.fast_forward_outlined, 'Valeurs par défaut appliquées')
        : (Icons.check_circle_outline, 'Réponses envoyées');

    return Container(
      key: const ValueKey('vibe-ask-user-resolved'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sélecteur de mode de vitesse du chat Vibe.
class VibeSpeedModeChip extends StatelessWidget {
  /// Crée une option de vitesse sélectionnable.
  const VibeSpeedModeChip({
    required this.mode,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  /// Mode de génération associé.
  final VibeAiSpeedMode mode;

  /// Icône affichée devant le nom du mode.
  final IconData icon;

  /// Indique si le mode est actif.
  final bool selected;

  /// Indique si la sélection est permise.
  final bool enabled;

  /// Callback déclenché à la sélection.
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    return Tooltip(
      message: mode.tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: mode.label,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('vibe-chat-speed-${mode.name}'),
            onTap: enabled ? onSelected : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur activant ou désactivant le mode « Plan » (découpage en lots validé avant exécution).
class VibePlanModeChip extends StatelessWidget {
  /// Crée une puce bascule pour le mode « Plan ».
  const VibePlanModeChip({
    required this.selected,
    required this.enabled,
    required this.onToggle,
    super.key,
  });

  /// Indique si le mode Plan est actif.
  final bool selected;

  /// Indique si le basculement est autorisé (désactivé pendant la génération).
  final bool enabled;

  /// Callback appelé au clic.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.secondaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final borderColor = selected ? scheme.secondary : scheme.outlineVariant;
    return Tooltip(
      message:
          'Mode Plan : découpe d’abord la demande en un plan par lots '
          'validé avant exécution séquentielle (cumulable avec Éclair/Rapide/Précis)',
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: 'Plan',
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('vibe-chat-plan-mode'),
            onTap: enabled ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_play_rounded,
                    size: 15,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Plan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur activant ou désactivant le mode « Reproduire à l'identique » (pixel-perfect).
class VibeReproduceExactChip extends StatelessWidget {
  /// Crée une puce bascule pour le mode « Reproduire à l'identique ».
  const VibeReproduceExactChip({
    required this.selected,
    required this.enabled,
    required this.onToggle,
    super.key,
  });

  /// Indique si le mode est actif.
  final bool selected;

  /// Indique si le basculement est autorisé (désactivé pendant la génération).
  final bool enabled;

  /// Callback appelé au clic.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onTertiaryContainer
        : scheme.onSurfaceVariant;
    final borderColor = selected ? scheme.tertiary : scheme.outlineVariant;
    return Tooltip(
      message:
          'Mode pixel-perfect : ignore le Design System générique et les questions '
          '(activer aussi « Plan » pour découper en lots)',
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: 'Reproduire à l’identique',
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('vibe-chat-reproduce-exact'),
            onTap: enabled ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.content_copy_outlined,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'À l’identique',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur activant ou désactivant le mode « Uniquement visible »
/// (verrouille l'onglet actif et la position de scroll courante pour le chat).
class VibeVisibleOnlyChip extends StatelessWidget {
  /// Crée une puce bascule pour le mode « Uniquement visible ».
  const VibeVisibleOnlyChip({
    required this.selected,
    required this.enabled,
    required this.onToggle,
    super.key,
  });

  /// Indique si le mode « Uniquement visible » est actif.
  final bool selected;

  /// Indique si le basculement est autorisé (désactivé pendant la génération).
  final bool enabled;

  /// Callback appelé au clic.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    return Tooltip(
      message:
          'Mode Scope Uniquement visible : reste sur l’onglet actif et la position de scroll '
          'actuelle pour toutes les opérations du chat (ajout, modification, audit, plan)',
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: 'Scope visible',
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('vibe-chat-visible-only'),
            onTap: enabled ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.visibility : Icons.visibility_outlined,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Scope visible',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur activant ou désactivant la passe de vérification visuelle
/// post-rendu (`verifyRender`) demandée par l'IA en fin de génération.
class VibeVerifyRenderChip extends StatelessWidget {
  /// Crée une puce bascule pour la vérification post-rendu `verifyRender`.
  const VibeVerifyRenderChip({
    required this.selected,
    required this.enabled,
    required this.onToggle,
    super.key,
  });

  /// Indique si la vérification visuelle post-rendu `verifyRender` est autorisée.
  final bool selected;

  /// Indique si le basculement est autorisé (désactivé pendant la génération).
  final bool enabled;

  /// Callback appelé au clic.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final borderColor = selected ? scheme.primary : scheme.outlineVariant;
    return Tooltip(
      message: selected
          ? 'Vérif. rendu active : contrôle local automatique après génération et correction IA uniquement si une anomalie est détectée (cliquer pour désactiver)'
          : 'Vérif. rendu désactivée : ignore verifyRender pour accélérer la fin de génération (les erreurs critiques restent corrigées)',
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        label: 'Vérif. rendu',
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('vibe-chat-verify-render'),
            onTap: enabled ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.fact_check : Icons.fact_check_outlined,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Vérif. rendu',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton lançant une génération orientée vers les valeurs calculées réactives.
class VibeReactiveValuesActionChip extends StatelessWidget {
  /// Crée la puce « Valeur réactif ».
  const VibeReactiveValuesActionChip({
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  /// Indique si le bouton est cliquable.
  final bool enabled;

  /// Callback déclenché au clic.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.secondary;
    return Tooltip(
      message:
          'Configurer les calculatedAttributes, les champs de saisie et '
          'les valeurs calculées en consultation',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Valeur réactif',
        child: Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('vibe-chat-reactive-values'),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calculate_outlined,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Valeur réactif',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton d'action déclenchant l'audit déterministe et la planification de corrections
/// de la page active (ou du scope ciblé).
class VibeAuditActionChip extends StatelessWidget {
  /// Crée la puce d'action « Audit & correction ».
  const VibeAuditActionChip({
    required this.enabled,
    required this.onPressed,
    this.scoped = false,
    this.visibleOnly = false,
    super.key,
  });

  /// Indique si le bouton est cliquable (désactivé pendant une génération).
  final bool enabled;

  /// Indique si l'audit porte sur un `VibeChatScope` restreint.
  final bool scoped;

  /// Indique si l'audit est restreint à l'onglet et au scroll actuellement visibles.
  final bool visibleOnly;

  /// Callback déclenché au clic.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.surfaceContainerLow;
    final foreground = scheme.primary;
    final borderColor = scheme.outlineVariant;
    return Tooltip(
      message: scoped
          ? 'Auditer ce périmètre (marges coupées, débordements, calculs @calculs manquants, contrastes) et préparer un plan de correction'
          : visibleOnly
          ? 'Auditer uniquement la zone visible (onglet actif et position de scroll courante) et préparer un plan de correction'
          : 'Auditer la page active (marges coupées, débordements, calculs @calculs manquants, contrastes) et préparer un plan de correction',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Audit & correction',
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('vibe-chat-audit-page'),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.troubleshoot_outlined,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Audit & correction',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? foreground
                          : foreground.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bulle présentant progressivement le texte et l'état du patch généré.
class VibeStreamingAssistantBubble extends StatelessWidget {
  /// Crée la bulle liée aux snapshots de [snapshot].
  const VibeStreamingAssistantBubble({
    required this.snapshot,
    this.onCancel,
    super.key,
  });

  /// Snapshot réactif du parseur de réponse incrémental.
  final ValueListenable<VibeStreamSnapshot?> snapshot;

  /// Callback optionnel déclenché pour annuler l'appel IA en cours.
  final VoidCallback? onCancel;

  Widget _buildCancelButton(ColorScheme scheme) => Align(
    alignment: Alignment.centerRight,
    child: Tooltip(
      message: 'Annuler l’appel IA en cours',
      child: TextButton.icon(
        key: const ValueKey('vibe-chat-streaming-cancel'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.error,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onCancel,
        icon: const Icon(Icons.stop_circle_outlined, size: 15),
        label: const Text('Annuler', style: TextStyle(fontSize: 12)),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 340.0;
        final maxBubbleWidth = math.max(
          340.0,
          math.min(820.0, availableWidth * 0.80),
        );
        return Align(
          key: const ValueKey('vibe-chat-streaming-bubble'),
          alignment: Alignment.centerLeft,
          child: ValueListenableBuilder<VibeStreamSnapshot?>(
            valueListenable: snapshot,
            builder: (context, current, _) {
              final streamedMessage = current?.message;
              final activeToolStatus = current?.activeToolStatus;
              final activePhaseLabel = current?.activePhaseLabel;
              final elapsedMs = current?.elapsedMs;
              final completedTraces =
                  current?.toolTraces ?? const <VibeToolTrace>[];
              final timedTraces =
                  current?.timedTraces ?? const <VibeTimedTrace>[];
              if (current == null || streamedMessage == null) {
                return Container(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (activePhaseLabel != null || elapsedMs != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (activePhaseLabel != null)
                                Flexible(
                                  child: Text(
                                    activePhaseLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              if (elapsedMs != null) ...[
                                if (activePhaseLabel != null)
                                  const SizedBox(width: 6),
                                Text(
                                  formatVibeDuration(elapsedMs),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontFamily: 'monospace',
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      for (final trace in timedTraces)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            trace.formatLine(),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              color: trace.isError
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      for (final trace in completedTraces)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _VibeToolTraceRow(trace: trace),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              activeToolStatus ?? 'Génération en cours…',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (onCancel != null) ...[
                        const SizedBox(height: 6),
                        _buildCancelButton(scheme),
                      ],
                    ],
                  ),
                );
              }

              final count = current.estimatedComponentCount;
              final patchLabel = count > 0
                  ? 'Construction du patch UI ($count composant${count > 1 ? 's' : ''})…'
                  : 'Construction du patch UI…';
              final repoCount = current.partialRepositoriesPatch?.length ?? 0;
              final repoLabel = repoCount > 0
                  ? 'Préparation des repositories ($repoCount)…'
                  : 'Préparation des repositories…';

              return Container(
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (activePhaseLabel != null || elapsedMs != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (activePhaseLabel != null)
                              Flexible(
                                child: Text(
                                  activePhaseLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            if (elapsedMs != null) ...[
                              if (activePhaseLabel != null)
                                const SizedBox(width: 6),
                              Text(
                                formatVibeDuration(elapsedMs),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    for (final trace in timedTraces)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          trace.formatLine(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: trace.isError
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final trace in completedTraces)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _VibeToolTraceRow(trace: trace),
                      ),
                    SelectableText(streamedMessage),
                    if (current.hasVibeObject) ...[
                      if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              patchLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (current.hasRepositoriesObject) ...[
                      if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              repoLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (activeToolStatus != null ||
                        (current.isMessageComplete &&
                            current.hasToolCallsObject)) ...[
                      if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              activeToolStatus ??
                                  'Inspection de l’application en cours…',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (current.isMessageComplete &&
                        current.hasPlanObject) ...[
                      if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Découpage du plan en lots…',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else if (current.isMessageComplete &&
                        current.hasAskUserObject) ...[
                      if (streamedMessage.isNotEmpty) const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Préparation des questions…',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (onCancel != null) ...[
                      const SizedBox(height: 6),
                      _buildCancelButton(scheme),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
