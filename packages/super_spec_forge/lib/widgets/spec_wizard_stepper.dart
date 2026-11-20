/// Barre de navigation horizontale des 5 étapes du wizard IA ([SpecWizardStepper]).
library;

import 'package:material_ui/material_ui.dart';

import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';

/// Affiche la progression dans les 5 étapes spécialisées et permet de naviguer entre elles.
class SpecWizardStepper extends StatelessWidget {
  /// Crée la barre de progression pour [project].
  const SpecWizardStepper({
    required this.project,
    required this.onSelectStage,
    this.disabled = false,
    super.key,
  });

  /// Projet courant.
  final SpecForgeProject project;

  /// Callback appelé lors du clic sur une étape.
  final ValueChanged<SpecForgeStage> onSelectStage;

  /// Désactive le changement d'étape pendant une génération IA si souhaité.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < SpecForgeStage.values.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
              ),
            Expanded(
              child: _StageStepTile(
                stage: SpecForgeStage.values[i],
                status: project.stageStateFor(SpecForgeStage.values[i]).status,
                isActive: project.currentStage == SpecForgeStage.values[i],
                onTap: disabled
                    ? null
                    : () => onSelectStage(SpecForgeStage.values[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageStepTile extends StatelessWidget {
  const _StageStepTile({
    required this.stage,
    required this.status,
    required this.isActive,
    required this.onTap,
  });

  final SpecForgeStage stage;
  final SpecStageStatus status;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final Color bgColor;
    final Color borderColor;
    final Color fgColor;
    if (isActive) {
      bgColor = colors.primaryContainer;
      borderColor = colors.primary;
      fgColor = colors.onPrimaryContainer;
    } else if (status == SpecStageStatus.validated) {
      bgColor = colors.secondaryContainer.withValues(alpha: 0.6);
      borderColor = colors.secondary.withValues(alpha: 0.5);
      fgColor = colors.onSecondaryContainer;
    } else {
      bgColor = colors.surface;
      borderColor = colors.outlineVariant;
      fgColor = colors.onSurfaceVariant;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: isActive
                  ? colors.primary
                  : (status == SpecStageStatus.validated
                        ? colors.secondary
                        : colors.surfaceContainerHighest),
              child: status == SpecStageStatus.validated && !isActive
                  ? Icon(Icons.check_rounded, size: 15, color: colors.onSecondary)
                  : Text(
                      '${stage.stepNumber}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    stage.shortLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: fgColor,
                    ),
                  ),
                  Text(
                    stage.agentTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: fgColor.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
