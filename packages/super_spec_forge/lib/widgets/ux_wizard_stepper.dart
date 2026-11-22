/// Barre de navigation horizontale des 4 étapes du wizard UX ([UxWizardStepper]).
library;

import 'package:material_ui/material_ui.dart';

import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';
import '../models/ux/ux_forge_stage.dart';

/// Affiche la progression dans les 4 étapes UX spécialisées et permet de naviguer entre elles.
class UxWizardStepper extends StatelessWidget {
  /// Crée la barre de progression UX pour [project].
  const UxWizardStepper({
    required this.project,
    required this.onSelectStage,
    this.onBack,
    this.onSwitchToSpecWizard,
    this.onSwitchToQaWizard,
    this.disabled = false,
    super.key,
  });

  /// Projet courant.
  final SpecForgeProject project;

  /// Callback appelé lors du clic sur une étape UX.
  final ValueChanged<UxForgeStage> onSelectStage;

  /// Callback optionnel de retour vers le menu Spec.
  final VoidCallback? onBack;

  /// Callback optionnel permettant de basculer vers le Wizard de spécification métier.
  final VoidCallback? onSwitchToSpecWizard;

  /// Callback optionnel permettant de basculer vers le Wizard BDD / Gherkin & TDD.
  final VoidCallback? onSwitchToQaWizard;

  /// Désactive le changement d'étape pendant une génération IA si souhaité.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      key: const ValueKey('ux-wizard-stepper'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (onBack != null) ...[
            OutlinedButton.icon(
              key: const ValueKey('ux-subview-back-btn'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Spec'),
            ),
            SizedBox(width: onSwitchToSpecWizard != null ? 8 : 12),
          ],
          if (onSwitchToSpecWizard != null) ...[
            Tooltip(
              message: 'Basculer vers le Wizard de spécification métier',
              child: TextButton.icon(
                key: const ValueKey('ux-switch-to-spec-wizard-btn'),
                onPressed: onSwitchToSpecWizard,
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Wizard Métier'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          for (var i = 0; i < UxForgeStage.values.length; i++) ...[
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
              child: _UxStageStepTile(
                stage: UxForgeStage.values[i],
                status: project.uxSpec
                    .stageStateFor(UxForgeStage.values[i])
                    .status,
                isActive:
                    project.uxSpec.currentStage == UxForgeStage.values[i],
                onTap: disabled
                    ? null
                    : () => onSelectStage(UxForgeStage.values[i]),
              ),
            ),
          ],
          if (onSwitchToQaWizard != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              key: const ValueKey('ux-switch-to-qa-wizard-btn'),
              onPressed: disabled ? null : onSwitchToQaWizard,
              icon: const Icon(Icons.science_outlined, size: 16),
              label: const Text('BDD / TDD'),
            ),
          ],
        ],
      ),
    );
  }
}

class _UxStageStepTile extends StatelessWidget {
  const _UxStageStepTile({
    required this.stage,
    required this.status,
    required this.isActive,
    required this.onTap,
  });

  final UxForgeStage stage;
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
      key: ValueKey('ux-step-tile-${stage.name}'),
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
                  ? Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: colors.onSecondary,
                    )
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
