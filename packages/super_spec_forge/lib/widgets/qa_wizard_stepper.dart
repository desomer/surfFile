/// Barre de navigation horizontale des 4 étapes du wizard QA BDD/Gherkin & TDD ([QaWizardStepper]).
library;

import 'package:material_ui/material_ui.dart';

import '../models/qa/qa_forge_stage.dart';
import '../models/spec_forge_project.dart';
import '../models/spec_forge_stage.dart';

/// Affiche la progression dans les 4 étapes QA spécialisées et permet de naviguer entre elles.
class QaWizardStepper extends StatelessWidget {
  /// Crée la barre de progression QA pour [project].
  const QaWizardStepper({
    required this.project,
    required this.onSelectStage,
    this.onBack,
    this.onSwitchToSpecWizard,
    this.onSwitchToUxWizard,
    this.disabled = false,
    super.key,
  });

  /// Projet courant.
  final SpecForgeProject project;

  /// Callback appelé lors du clic sur une étape QA.
  final ValueChanged<QaForgeStage> onSelectStage;

  /// Callback optionnel de retour vers le menu Spec.
  final VoidCallback? onBack;

  /// Callback optionnel permettant de basculer vers le Wizard de spécification métier.
  final VoidCallback? onSwitchToSpecWizard;

  /// Callback optionnel permettant de basculer vers le Wizard UX & Parcours.
  final VoidCallback? onSwitchToUxWizard;

  /// Désactive le changement d'étape pendant une génération IA si souhaité.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasNavButtons =
        onBack != null ||
        onSwitchToSpecWizard != null ||
        onSwitchToUxWizard != null;

    return Container(
      key: const ValueKey('qa-wizard-stepper'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final stackNavButtons = hasNavButtons && maxWidth < 680;
          final showChevrons = maxWidth >= 440;
          final horizontalPadding = maxWidth < 440 ? 8.0 : 16.0;

          final navButtons = <Widget>[
            if (onBack != null)
              OutlinedButton.icon(
                key: const ValueKey('qa-subview-back-btn'),
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Spec'),
              ),
            if (onSwitchToSpecWizard != null)
              Tooltip(
                message: 'Basculer vers le Wizard de spécification métier',
                child: TextButton.icon(
                  key: const ValueKey('qa-switch-to-spec-wizard-btn'),
                  onPressed: disabled ? null : onSwitchToSpecWizard,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Métier'),
                ),
              ),
            if (onSwitchToUxWizard != null)
              Tooltip(
                message: 'Basculer vers le Wizard UX & Parcours',
                child: TextButton.icon(
                  key: const ValueKey('qa-switch-to-ux-wizard-btn'),
                  onPressed: disabled ? null : onSwitchToUxWizard,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.design_services_outlined, size: 16),
                  label: const Text('UX'),
                ),
              ),
          ];

          final stepTilesRow = Row(
            children: [
              if (!stackNavButtons && navButtons.isNotEmpty) ...[
                for (var b = 0; b < navButtons.length; b++) ...[
                  if (b > 0) const SizedBox(width: 6),
                  navButtons[b],
                ],
                const SizedBox(width: 10),
              ],
              for (var i = 0; i < QaForgeStage.values.length; i++) ...[
                if (i > 0)
                  showChevrons
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : const SizedBox(width: 4),
                Expanded(
                  child: _QaStageStepTile(
                    stage: QaForgeStage.values[i],
                    status: project.qaSpec
                        .stageStateFor(QaForgeStage.values[i])
                        .status,
                    isActive:
                        project.qaSpec.currentStage == QaForgeStage.values[i],
                    onTap: disabled
                        ? null
                        : () => onSelectStage(QaForgeStage.values[i]),
                  ),
                ),
              ],
            ],
          );

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 10,
            ),
            child: stackNavButtons
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: navButtons,
                      ),
                      const SizedBox(height: 8),
                      stepTilesRow,
                    ],
                  )
                : stepTilesRow,
          );
        },
      ),
    );
  }
}

class _QaStageStepTile extends StatelessWidget {
  const _QaStageStepTile({
    required this.stage,
    required this.status,
    required this.isActive,
    required this.onTap,
  });

  final QaForgeStage stage;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTight = constraints.maxWidth < 76;
        final horizontalPad = isTight ? 4.0 : 10.0;
        final avatarRadius = isTight ? 10.0 : 13.0;
        final gap = isTight ? 4.0 : 8.0;

        return InkWell(
          key: ValueKey('qa-step-tile-${stage.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: isActive
                      ? colors.primary
                      : (status == SpecStageStatus.validated
                            ? colors.secondary
                            : colors.surfaceContainerHighest),
                  child: status == SpecStageStatus.validated && !isActive
                      ? Icon(
                          Icons.check_rounded,
                          size: isTight ? 12 : 15,
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
                SizedBox(width: gap),
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
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w600,
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
      },
    );
  }
}
