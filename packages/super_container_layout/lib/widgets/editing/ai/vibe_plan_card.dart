/// Carte interactive d'affichage et de pilotage d'un plan par lots ([VibePlanCard])
/// pour le mode « Plan » (et sa combinaison avec « Reproduire à l'identique ») du chat Vibe IA.
library;

import 'package:material_ui/material_ui.dart';

import '../../../ai/vibe_plan.dart';

/// Carte interactive affichant les lots d'un [VibeExecutionPlan] et ses commandes de contrôle.
class VibePlanCard extends StatelessWidget {
  /// Crée une carte de suivi et de contrôle pour [plan].
  const VibePlanCard({
    required this.plan,
    required this.busy,
    this.isActivePlan = true,
    this.onStart,
    this.onCancel,
    this.onStop,
    this.onRetryLot,
    this.onSkipLot,
    this.onToggleLot,
    super.key,
  });

  /// Plan découpé en lots à afficher.
  final VibeExecutionPlan plan;

  /// Indique si une génération IA est actuellement en cours.
  final bool busy;

  /// Indique si ce plan est le plan interactif courant (permet les actions).
  final bool isActivePlan;

  /// Déclenché au clic sur « Exécuter les lots ».
  final VoidCallback? onStart;

  /// Déclenché au clic sur « Annuler » avant le démarrage du plan.
  final VoidCallback? onCancel;

  /// Déclenché au clic sur « Arrêter » pendant ou après erreur sur l'exécution.
  final VoidCallback? onStop;

  /// Déclenché au clic sur « Réessayer ce lot » lorsqu'un lot est en échec.
  final VoidCallback? onRetryLot;

  /// Déclenché au clic sur « Ignorer ce lot » lorsqu'un lot est en échec.
  final VoidCallback? onSkipLot;

  /// Déclenché lors de l'activation ou de la désactivation d'un lot en attente.
  final ValueChanged<int>? onToggleLot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = plan.lots.length;
    final finished = plan.finishedCount;
    final actionable = plan.actionableCount;
    final canToggleLots =
        isActivePlan && plan.status == VibePlanStatus.awaitingConfirmation;

    final (IconData headerIcon, Color headerColor) = switch (plan.status) {
      VibePlanStatus.awaitingConfirmation => (
        Icons.playlist_play_rounded,
        scheme.primary,
      ),
      VibePlanStatus.running => (Icons.sync_rounded, scheme.primary),
      VibePlanStatus.pausedOnError => (
        Icons.pause_circle_outline,
        scheme.error,
      ),
      VibePlanStatus.completed => (
        Icons.check_circle_outline,
        scheme.primary,
      ),
      VibePlanStatus.stopped => (
        Icons.stop_circle_outlined,
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      key: const ValueKey('vibe-plan-card'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: plan.status == VibePlanStatus.pausedOnError
              ? scheme.error.withValues(alpha: 0.6)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(headerIcon, size: 18, color: headerColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  plan.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: plan.status == VibePlanStatus.pausedOnError
                      ? scheme.errorContainer
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$finished/$total lots',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: plan.status == VibePlanStatus.pausedOnError
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (plan.status == VibePlanStatus.running && total > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: finished / total,
                minHeight: 4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final (index, lot) in plan.lots.indexed) ...[
            if (index > 0) const SizedBox(height: 5),
            _LotRow(
              index: index,
              lot: lot,
              canToggle: canToggleLots && !busy,
              onToggle: onToggleLot,
            ),
          ],
          if (isActivePlan) ...[
            if (plan.status == VibePlanStatus.awaitingConfirmation) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('vibe-plan-cancel'),
                    onPressed: busy ? null : onCancel,
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('vibe-plan-start'),
                    onPressed: busy || actionable == 0 ? null : onStart,
                    icon: const Icon(Icons.play_arrow, size: 17),
                    label: Text(
                      actionable == 0
                          ? 'Aucun lot activé'
                          : actionable == 1
                          ? 'Exécuter le lot'
                          : 'Exécuter les $actionable lots',
                    ),
                  ),
                ],
              ),
            ] else if (plan.status == VibePlanStatus.running) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('vibe-plan-stop'),
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_outlined, size: 17),
                    label: const Text('Arrêter'),
                  ),
                ],
              ),
            ] else if (plan.status == VibePlanStatus.pausedOnError) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton(
                    key: const ValueKey('vibe-plan-stop'),
                    onPressed: busy ? null : onStop,
                    child: const Text('Arrêter le plan'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('vibe-plan-skip-lot'),
                    onPressed: busy ? null : onSkipLot,
                    icon: const Icon(Icons.skip_next, size: 17),
                    label: const Text('Ignorer ce lot'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('vibe-plan-retry-lot'),
                    onPressed: busy ? null : onRetryLot,
                    icon: const Icon(Icons.refresh, size: 17),
                    label: const Text('Réessayer ce lot'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LotRow extends StatelessWidget {
  const _LotRow({
    required this.index,
    required this.lot,
    required this.canToggle,
    required this.onToggle,
  });

  final int index;
  final VibePlanLot lot;
  final bool canToggle;
  final ValueChanged<int>? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRunning = lot.status == VibeLotStatus.running;
    final isFailed = lot.status == VibeLotStatus.failed;
    final isDone = lot.status == VibeLotStatus.done;
    final isDisabled = lot.status == VibeLotStatus.disabled;

    final Widget leadingIcon = switch (lot.status) {
      VibeLotStatus.pending => Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: scheme.onSurfaceVariant,
      ),
      VibeLotStatus.running => const SizedBox.square(
        dimension: 15,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      VibeLotStatus.done => Icon(
        Icons.check_circle,
        size: 16,
        color: scheme.primary,
      ),
      VibeLotStatus.failed => Icon(
        Icons.error_outline,
        size: 16,
        color: scheme.error,
      ),
      VibeLotStatus.skipped => Icon(
        Icons.skip_next_outlined,
        size: 16,
        color: scheme.onSurfaceVariant,
      ),
      VibeLotStatus.disabled => Icon(
        Icons.do_not_disturb_on_outlined,
        size: 16,
        color: scheme.onSurfaceVariant,
      ),
    };

    return Container(
      key: ValueKey('vibe-plan-lot-${lot.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isFailed
            ? scheme.errorContainer.withValues(alpha: 0.45)
            : isRunning
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : isDisabled
            ? scheme.surfaceContainerLow.withValues(alpha: 0.55)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFailed
              ? scheme.error.withValues(alpha: 0.5)
              : isRunning
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: leadingIcon,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${index + 1}. ${lot.title}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isRunning || isFailed
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: isDone
                        ? scheme.onSurface
                        : lot.status == VibeLotStatus.skipped || isDisabled
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                    decoration:
                        lot.status == VibeLotStatus.skipped || isDisabled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (lot.description.isNotEmpty &&
                    lot.description != lot.title) ...[
                  const SizedBox(height: 2),
                  Text(
                    lot.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (isFailed &&
                    lot.errorMessage != null &&
                    lot.errorMessage!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    lot.errorMessage!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canToggle)
            Tooltip(
              message: isDisabled ? 'Activer ce lot' : 'Désactiver ce lot',
              child: Checkbox(
                key: ValueKey('vibe-plan-lot-toggle-${lot.id}'),
                value: !isDisabled,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => onToggle?.call(index),
              ),
            ),
        ],
      ),
    );
  }
}
