/// Composants d'interface et dialogues partagés de gouvernance des jalons
/// d'itération ([DomainIterationSnapshot]), de suivi de dérive inter-itérations
/// et de recommandation SemVer ([DomainIterationSnapshotBar],
/// [EvolutionDriftBadge], [SemVerBumpActionChip],
/// [CreateIterationSnapshotDialog], [ManageIterationSnapshotsDialog],
/// [ArtifactEvolutionDiffDialog], [DomainEvolutionSummaryDialog]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/domain_catalog.dart';
import '../../models/domain_iteration_snapshot.dart';
import '../../models/value_object_spec.dart';
import '../../services/design_evolution_analyzer.dart';
import '../../services/spec_forge_controller.dart';

const String _kMenuActionDisableBaseline = '_disable_baseline_';
const String _kMenuActionManageSnapshots = '_manage_snapshots_';
const String _kMenuPrefixSelectSnapshot = 'select_snapshot:';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _formatDateShort(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
}

String _formatDateTimeLocal(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _formatDateTimeUtc(DateTime dateTime) {
  final utc = dateTime.toUtc();
  return '${utc.year}-${_twoDigits(utc.month)}-${_twoDigits(utc.day)} '
      '${_twoDigits(utc.hour)}:${_twoDigits(utc.minute)} UTC';
}

List<DomainIterationSnapshot> _sortedSnapshotsNewestFirst(
  Iterable<DomainIterationSnapshot> snapshots,
) {
  final list = List<DomainIterationSnapshot>.of(snapshots);
  list.sort((a, b) {
    final iterCmp = b.iterationNumber.compareTo(a.iterationNumber);
    if (iterCmp != 0) return iterCmp;
    return b.createdAt.compareTo(a.createdAt);
  });
  return list;
}

({Color bg, Color fg, Color border}) _paletteForState(
  ArtifactEvolutionState state,
  SemVerBump bump,
  ColorScheme colors,
) {
  final isDark = colors.brightness == Brightness.dark;
  switch (state) {
    case ArtifactEvolutionState.added:
      final fg = isDark ? Colors.teal.shade200 : Colors.teal.shade800;
      return (
        bg: Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12),
        fg: fg,
        border: Colors.teal.withValues(alpha: isDark ? 0.50 : 0.35),
      );
    case ArtifactEvolutionState.modified:
      if (bump == SemVerBump.major) {
        final fg = isDark
            ? Colors.deepOrange.shade200
            : Colors.deepOrange.shade900;
        return (
          bg: Colors.deepOrange.withValues(alpha: isDark ? 0.24 : 0.12),
          fg: fg,
          border: Colors.deepOrange.withValues(alpha: isDark ? 0.55 : 0.38),
        );
      }
      final fg = isDark ? Colors.amber.shade200 : Colors.orange.shade900;
      return (
        bg: Colors.orange.withValues(alpha: isDark ? 0.22 : 0.13),
        fg: fg,
        border: Colors.orange.withValues(alpha: isDark ? 0.50 : 0.38),
      );
    case ArtifactEvolutionState.impacted:
      final fg = isDark ? Colors.indigo.shade200 : Colors.indigo.shade800;
      return (
        bg: Colors.indigo.withValues(alpha: isDark ? 0.24 : 0.11),
        fg: fg,
        border: Colors.indigo.withValues(alpha: isDark ? 0.52 : 0.34),
      );
    case ArtifactEvolutionState.removed:
      final fg = isDark ? Colors.red.shade200 : Colors.red.shade800;
      return (
        bg: Colors.red.withValues(alpha: isDark ? 0.22 : 0.11),
        fg: fg,
        border: Colors.red.withValues(alpha: isDark ? 0.52 : 0.36),
      );
    case ArtifactEvolutionState.unchanged:
      final fg = isDark ? Colors.green.shade200 : Colors.green.shade800;
      return (
        bg: Colors.green.withValues(alpha: isDark ? 0.20 : 0.11),
        fg: fg,
        border: Colors.green.withValues(alpha: isDark ? 0.46 : 0.32),
      );
    case ArtifactEvolutionState.noBaseline:
      return (
        bg: colors.surfaceContainerHighest,
        fg: colors.onSurfaceVariant,
        border: colors.outlineVariant,
      );
  }
}

({Color bg, Color fg, Color border}) _paletteForSemVerBump(
  SemVerBump bump,
  ColorScheme colors,
) {
  final isDark = colors.brightness == Brightness.dark;
  return switch (bump) {
    SemVerBump.major => (
      bg: Colors.deepOrange.withValues(alpha: isDark ? 0.24 : 0.12),
      fg: isDark ? Colors.deepOrange.shade200 : Colors.deepOrange.shade900,
      border: Colors.deepOrange.withValues(alpha: isDark ? 0.55 : 0.38),
    ),
    SemVerBump.minor => (
      bg: Colors.orange.withValues(alpha: isDark ? 0.22 : 0.13),
      fg: isDark ? Colors.amber.shade200 : Colors.orange.shade900,
      border: Colors.orange.withValues(alpha: isDark ? 0.50 : 0.36),
    ),
    SemVerBump.patch => (
      bg: Colors.blue.withValues(alpha: isDark ? 0.22 : 0.11),
      fg: isDark ? Colors.lightBlue.shade200 : Colors.blue.shade800,
      border: Colors.blue.withValues(alpha: isDark ? 0.48 : 0.34),
    ),
    SemVerBump.none => (
      bg: colors.surfaceContainerHighest,
      fg: colors.onSurfaceVariant,
      border: colors.outlineVariant,
    ),
  };
}

IconData _iconForArtifactKind(DesignArtifactKind kind) => switch (kind) {
  DesignArtifactKind.valueObject => Icons.diamond_outlined,
  DesignArtifactKind.model => Icons.account_tree_outlined,
  DesignArtifactKind.useCase => Icons.bolt_rounded,
  DesignArtifactKind.saga => Icons.route_outlined,
};

({String symbol, String text, Color fg, Color bg, Color border})
_classifyChangeEntry(ArtifactChangeEntry entry, ColorScheme colors) {
  final isDark = colors.brightness == Brightness.dark;
  final trimmed = entry.summary.trim();
  if (trimmed.startsWith('+')) {
    final rest = trimmed.substring(1).trimLeft();
    return (
      symbol: '+',
      text: rest.isEmpty ? trimmed : rest,
      fg: isDark ? Colors.teal.shade200 : Colors.teal.shade800,
      bg: Colors.teal.withValues(alpha: isDark ? 0.22 : 0.12),
      border: Colors.teal.withValues(alpha: isDark ? 0.50 : 0.35),
    );
  }
  if (trimmed.startsWith('-')) {
    final rest = trimmed.substring(1).trimLeft();
    return (
      symbol: '-',
      text: rest.isEmpty ? trimmed : rest,
      fg: isDark ? Colors.red.shade200 : Colors.red.shade800,
      bg: Colors.red.withValues(alpha: isDark ? 0.22 : 0.12),
      border: Colors.red.withValues(alpha: isDark ? 0.52 : 0.36),
    );
  }
  final rest = trimmed.startsWith('~')
      ? trimmed.substring(1).trimLeft()
      : trimmed;
  return (
    symbol: '~',
    text: rest.isEmpty ? trimmed : rest,
    fg: isDark ? Colors.amber.shade200 : Colors.orange.shade900,
    bg: Colors.orange.withValues(alpha: isDark ? 0.22 : 0.12),
    border: Colors.orange.withValues(alpha: isDark ? 0.50 : 0.36),
  );
}

String _buildBumpReasonTooltip(ArtifactEvolutionReport report) {
  final bumpLabel = report.effectiveBump.label;
  final fromVer = report.baselineVersion ?? report.currentVersion;
  if (report.state == ArtifactEvolutionState.modified) {
    final directCount = report.directChanges.length;
    final upstreamSuffix = report.impactedBy.isEmpty
        ? ''
        : ' + ${report.impactedBy.length} impact(s) amont';
    return 'Modification détectée ($directCount changement(s)$upstreamSuffix · '
        'impact $bumpLabel) depuis v$fromVer. '
        'Cliquer pour passer en v${report.recommendedVersion}.';
  }
  if (report.state == ArtifactEvolutionState.impacted) {
    final causes = report.impactedBy.take(3).join(' · ');
    final more = report.impactedBy.length > 3 ? '…' : '';
    return 'Impact transitif ($bumpLabel) via $causes$more depuis v$fromVer. '
        'Cliquer pour passer en v${report.recommendedVersion}.';
  }
  return 'Incrément SemVer recommandé ($bumpLabel) : '
      'v${report.currentVersion} → v${report.recommendedVersion}.';
}

Widget _buildStyledPill({
  Key? key,
  required String label,
  IconData? icon,
  required Color backgroundColor,
  required Color foregroundColor,
  required Color borderColor,
  bool compact = false,
  VoidCallback? onTap,
}) {
  final radius = BorderRadius.circular(compact ? 6 : 999);
  final padH = compact ? 7.0 : 9.0;
  final padV = compact ? 2.5 : 4.0;
  final fontSize = compact ? 11.0 : 12.0;
  final iconSize = compact ? 13.0 : 14.0;

  final content = Container(
    padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: radius,
      border: Border.all(color: borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (icon != null) Icon(icon, size: iconSize, color: foregroundColor),
        Text(
          label,
          style: TextStyle(
            color: foregroundColor,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  if (onTap == null) {
    return KeyedSubtree(key: key, child: content);
  }

  return Material(
    color: Colors.transparent,
    child: InkWell(
      key: key,
      borderRadius: radius,
      mouseCursor: SystemMouseCursors.click,
      hoverColor: foregroundColor.withValues(alpha: 0.08),
      splashColor: foregroundColor.withValues(alpha: 0.14),
      onTap: onTap,
      child: content,
    ),
  );
}

/// Barre horizontale contextuelle de sélection du jalon d'itération de référence,
/// de synthèse de dérive (`Conforme`, `+nouveaux`, `Δ modifiés`, `⇄ impactés`,
/// `-supprimés`) et de capture d'un nouveau [DomainIterationSnapshot].
class DomainIterationSnapshotBar extends StatelessWidget {
  /// Crée une barre de gouvernance des jalons d'itération pour [domain].
  const DomainIterationSnapshotBar({
    required this.controller,
    required this.domain,
    this.evolutionReport,
    this.compact = false,
    super.key,
  });

  /// Contrôleur d'orchestration et de persistance du catalogue de domaines.
  final SpecForgeController controller;

  /// Domaine fonctionnel ciblé par la barre.
  final FunctionalDomain domain;

  /// Rapport d'évolution précalculé optionnel ; s'il est omis ou si le catalogue
  /// évolue, il est calculé via [SpecForgeController.analyzeDomainEvolution].
  final DomainEvolutionReport? evolutionReport;

  /// Active un affichage condensé adapté aux barres secondaires ou panneaux étroits.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final initialCatalog = controller.domainCatalog;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final currentCatalog = controller.domainCatalog;
        final effectiveDomain =
            currentCatalog.domains
                .where((d) => d.id == domain.id)
                .firstOrNull ??
            domain;
        final report =
            (evolutionReport != null &&
                identical(currentCatalog, initialCatalog))
            ? evolutionReport!
            : controller.analyzeDomainEvolution(effectiveDomain.id);

        return _buildBarContent(context, effectiveDomain, report);
      },
    );
  }

  Widget _buildBarContent(
    BuildContext context,
    FunctionalDomain effectiveDomain,
    DomainEvolutionReport report,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activeBaseline =
        report.baseline ?? effectiveDomain.activeBaselineSnapshot;
    final sortedSnapshots = _sortedSnapshotsNewestFirst(
      effectiveDomain.iterationSnapshots,
    );

    final selectorLabel = activeBaseline == null
        ? 'Jalon de référence : Aucun'
        : '${activeBaseline.label} (Itération #${activeBaseline.iterationNumber} · '
              '${_formatDateShort(activeBaseline.createdAt)})';

    Future<void> openSummary() => DomainEvolutionSummaryDialog.show(
      context,
      controller: controller,
      domain: effectiveDomain,
    );

    final compliantPalette = _paletteForState(
      ArtifactEvolutionState.unchanged,
      SemVerBump.none,
      colors,
    );
    final addedPalette = _paletteForState(
      ArtifactEvolutionState.added,
      SemVerBump.minor,
      colors,
    );
    final modifiedPalette = _paletteForState(
      ArtifactEvolutionState.modified,
      SemVerBump.minor,
      colors,
    );
    final impactedPalette = _paletteForState(
      ArtifactEvolutionState.impacted,
      SemVerBump.minor,
      colors,
    );
    final removedPalette = _paletteForState(
      ArtifactEvolutionState.removed,
      SemVerBump.major,
      colors,
    );

    final selectorPill = PopupMenuButton<String>(
      key: ValueKey('snapshot-bar-selector-${effectiveDomain.id}'),
      tooltip: 'Choisir ou gérer le jalon d’itération de référence',
      constraints: const BoxConstraints(minWidth: 260, maxWidth: 460),
      onSelected: (selection) async {
        if (selection == _kMenuActionDisableBaseline) {
          await controller.setActiveBaselineSnapshot(effectiveDomain.id, null);
          return;
        }
        if (selection == _kMenuActionManageSnapshots) {
          if (!context.mounted) return;
          await ManageIterationSnapshotsDialog.show(
            context,
            controller: controller,
            domainId: effectiveDomain.id,
          );
          return;
        }
        if (selection.startsWith(_kMenuPrefixSelectSnapshot)) {
          final snapId = selection.substring(_kMenuPrefixSelectSnapshot.length);
          await controller.setActiveBaselineSnapshot(
            effectiveDomain.id,
            snapId,
          );
        }
      },
      itemBuilder: (menuContext) => <PopupMenuEntry<String>>[
        if (sortedSnapshots.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Aucun jalon capturé pour ce domaine'),
          )
        else
          for (final snap in sortedSnapshots)
            PopupMenuItem<String>(
              key: ValueKey('snapshot-bar-option-${snap.id}'),
              value: '$_kMenuPrefixSelectSnapshot${snap.id}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Icon(
                    activeBaseline?.id == snap.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: activeBaseline?.id == snap.id
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  Flexible(
                    child: Text(
                      '${snap.label} (Itération #${snap.iterationNumber} · '
                      '${_formatDateShort(snap.createdAt)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        if (activeBaseline != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            key: ValueKey('snapshot-bar-disable-${effectiveDomain.id}'),
            value: _kMenuActionDisableBaseline,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Icon(Icons.visibility_off_outlined, size: 16),
                Flexible(
                  child: Text(
                    'Désactiver la comparaison',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: ValueKey('snapshot-bar-open-manage-${effectiveDomain.id}'),
          value: _kMenuActionManageSnapshots,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(Icons.history_rounded, size: 16),
              Flexible(
                child: Text(
                  'Gérer les jalons…',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: activeBaseline == null
              ? colors.surfaceContainerHighest.withValues(alpha: 0.65)
              : colors.secondaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: activeBaseline == null
                ? colors.outlineVariant
                : colors.secondary.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(
              activeBaseline == null
                  ? Icons.bookmark_border_rounded
                  : Icons.bookmark_rounded,
              size: compact ? 15 : 16,
              color: activeBaseline == null
                  ? colors.onSurfaceVariant
                  : colors.onSecondaryContainer,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: compact ? 260 : 380),
              child: Text(
                selectorLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w600,
                  color: activeBaseline == null
                      ? colors.onSurfaceVariant
                      : colors.onSecondaryContainer,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: activeBaseline == null
                  ? colors.onSurfaceVariant
                  : colors.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );

    final summaryWidgets = <Widget>[];
    if (report.hasBaseline) {
      if (report.totalActionableCount == 0 && report.removedCount == 0) {
        summaryWidgets.add(
          Tooltip(
            message:
                'Aucune dérive détectée depuis le jalon « ${activeBaseline?.label ?? ''} ».',
            child: _buildStyledPill(
              key: ValueKey('snapshot-bar-compliant-${effectiveDomain.id}'),
              label: 'Conforme au jalon',
              icon: Icons.verified_outlined,
              backgroundColor: compliantPalette.bg,
              foregroundColor: compliantPalette.fg,
              borderColor: compliantPalette.border,
              compact: compact,
              onTap: openSummary,
            ),
          ),
        );
      } else {
        if (report.addedCount > 0) {
          summaryWidgets.add(
            Tooltip(
              message: 'Voir les nouveaux artefacts depuis le jalon',
              child: _buildStyledPill(
                key: ValueKey(
                  'snapshot-bar-summary-added-${effectiveDomain.id}',
                ),
                label: '+${report.addedCount} nouveau(x)',
                backgroundColor: addedPalette.bg,
                foregroundColor: addedPalette.fg,
                borderColor: addedPalette.border,
                compact: compact,
                onTap: openSummary,
              ),
            ),
          );
        }
        if (report.modifiedCount > 0) {
          summaryWidgets.add(
            Tooltip(
              message:
                  'Voir les artefacts directement modifiés depuis le jalon',
              child: _buildStyledPill(
                key: ValueKey(
                  'snapshot-bar-summary-modified-${effectiveDomain.id}',
                ),
                label: 'Δ ${report.modifiedCount} modifié(s)',
                backgroundColor: modifiedPalette.bg,
                foregroundColor: modifiedPalette.fg,
                borderColor: modifiedPalette.border,
                compact: compact,
                onTap: openSummary,
              ),
            ),
          );
        }
        if (report.impactedCount > 0) {
          summaryWidgets.add(
            Tooltip(
              message: 'Voir les artefacts impactés par propagation transitive',
              child: _buildStyledPill(
                key: ValueKey(
                  'snapshot-bar-summary-impacted-${effectiveDomain.id}',
                ),
                label: '⇄ ${report.impactedCount} impacté(s)',
                backgroundColor: impactedPalette.bg,
                foregroundColor: impactedPalette.fg,
                borderColor: impactedPalette.border,
                compact: compact,
                onTap: openSummary,
              ),
            ),
          );
        }
        if (report.removedCount > 0) {
          summaryWidgets.add(
            Tooltip(
              message: 'Voir les artefacts supprimés depuis le jalon',
              child: _buildStyledPill(
                key: ValueKey(
                  'snapshot-bar-summary-removed-${effectiveDomain.id}',
                ),
                label: '-${report.removedCount} supprimé(s)',
                backgroundColor: removedPalette.bg,
                foregroundColor: removedPalette.fg,
                borderColor: removedPalette.border,
                compact: compact,
                onTap: openSummary,
              ),
            ),
          );
        }
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [selectorPill, ...summaryWidgets],
              ),
            ),
          ),
          if (effectiveDomain.iterationSnapshots.isNotEmpty)
            IconButton(
              key: ValueKey('snapshot-bar-manage-${effectiveDomain.id}'),
              tooltip: 'Historique des jalons',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.history_rounded, size: 18),
              onPressed: () => ManageIterationSnapshotsDialog.show(
                context,
                controller: controller,
                domainId: effectiveDomain.id,
              ),
            ),
          OutlinedButton.icon(
            key: ValueKey('snapshot-bar-capture-${effectiveDomain.id}'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: compact ? 4 : 6,
              ),
            ),
            icon: const Icon(Icons.bookmark_add_outlined, size: 16),
            label: const Text('Figer un jalon…'),
            onPressed: () => CreateIterationSnapshotDialog.show(
              context,
              controller: controller,
              domain: effectiveDomain,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge visuel indiquant l'état de dérive d'un artefact Design par rapport au
/// jalon d'itération actif (`Nouveau`, `Δ`, `⇄ Impacté`, `Supprimé`).
class EvolutionDriftBadge extends StatelessWidget {
  /// Crée un badge de dérive pour [report].
  const EvolutionDriftBadge({
    required this.report,
    this.onTap,
    this.compact = false,
    super.key,
  });

  /// Rapport d'évolution de l'artefact ; s'il est `null`, `noBaseline` ou
  /// `unchanged`, le widget ne rend rien.
  final ArtifactEvolutionReport? report;

  /// Action exécutée au clic (ex. ouverture de [ArtifactEvolutionDiffDialog]).
  final VoidCallback? onTap;

  /// Active un libellé court adapté aux listes denses et en-têtes compacts.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currentReport = report;
    if (currentReport == null ||
        currentReport.state == ArtifactEvolutionState.noBaseline ||
        currentReport.state == ArtifactEvolutionState.unchanged) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final palette = _paletteForState(
      currentReport.state,
      currentReport.effectiveBump,
      colors,
    );

    final String label;
    final String tooltip;
    switch (currentReport.state) {
      case ArtifactEvolutionState.added:
        label = 'Nouveau';
        tooltip =
            'Nouvel artefact créé depuis le jalon de référence '
            '(v${currentReport.currentVersion}).';
      case ArtifactEvolutionState.modified:
        final bumpLabel = currentReport.effectiveBump.shortLabel;
        label = (!compact && currentReport.baselineVersion != null)
            ? 'Δ depuis v${currentReport.baselineVersion} · $bumpLabel'
            : 'Δ $bumpLabel';
        tooltip =
            '${currentReport.directChanges.length} modification(s) directe(s) '
            'depuis v${currentReport.baselineVersion ?? '—'} '
            '(impact ${currentReport.effectiveBump.label}).';
      case ArtifactEvolutionState.impacted:
        label = '⇄ Impacté (${currentReport.impactedBy.length})';
        tooltip = currentReport.impactedBy.isEmpty
            ? 'Impacté par une dépendance amont '
                  '(${currentReport.effectiveBump.label}).'
            : 'Impacté par : ${currentReport.impactedBy.join(' · ')}';
      case ArtifactEvolutionState.removed:
        label = 'Supprimé';
        tooltip =
            'Artefact présent dans le jalon '
            '(v${currentReport.baselineVersion ?? currentReport.currentVersion}) '
            'et supprimé du domaine.';
      case ArtifactEvolutionState.noBaseline:
      case ArtifactEvolutionState.unchanged:
        return const SizedBox.shrink();
    }

    return Tooltip(
      message: onTap == null ? tooltip : '$tooltip\nCliquer pour voir le diff.',
      child: _buildStyledPill(
        label: label,
        backgroundColor: palette.bg,
        foregroundColor: palette.fg,
        borderColor: palette.border,
        compact: compact,
        onTap: onTap,
      ),
    );
  }
}

/// Puce d'action 1-clic proposant l'incrément sémantique recommandé
/// (`Bump vX.Y.Z → vA.B.C`) lorsqu'un artefact a évolué sans changement de version.
class SemVerBumpActionChip extends StatelessWidget {
  /// Crée une puce d'incrément SemVer pour [report].
  const SemVerBumpActionChip({
    required this.report,
    required this.onApplyVersion,
    this.compact = false,
    super.key,
  });

  /// Rapport d'évolution de l'artefact évalué.
  final ArtifactEvolutionReport? report;

  /// Callback recevant la version recommandée (`report.recommendedVersion`) au clic.
  final ValueChanged<String> onApplyVersion;

  /// Réduit légèrement les marges et la taille de police pour les lignes denses.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final currentReport = report;
    if (currentReport == null || !currentReport.needsVersionBump) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final palette = _paletteForSemVerBump(currentReport.effectiveBump, colors);
    final label =
        'Bump v${currentReport.currentVersion} → '
        'v${currentReport.recommendedVersion} '
        '(${currentReport.effectiveBump.shortLabel})';

    return Tooltip(
      message: _buildBumpReasonTooltip(currentReport),
      child: _buildStyledPill(
        label: label,
        icon: Icons.auto_fix_high_rounded,
        backgroundColor: palette.bg,
        foregroundColor: palette.fg,
        borderColor: palette.border,
        compact: compact,
        onTap: () => onApplyVersion(currentReport.recommendedVersion),
      ),
    );
  }
}

/// Dialogue modal de capture d'un nouveau jalon d'itération
/// ([DomainIterationSnapshot]) sur un [FunctionalDomain].
class CreateIterationSnapshotDialog extends StatefulWidget {
  /// Crée le dialogue de capture d'un jalon d'itération pour [domain].
  const CreateIterationSnapshotDialog({
    required this.controller,
    required this.domain,
    super.key,
  });

  /// Contrôleur persistant le snapshot dans le catalogue de domaines.
  final SpecForgeController controller;

  /// Domaine fonctionnel dont l'état courant sera photographié.
  final FunctionalDomain domain;

  /// Ouvre le dialogue modal et retourne le [DomainIterationSnapshot] créé,
  /// ou `null` en cas d'annulation.
  static Future<DomainIterationSnapshot?> show(
    BuildContext context, {
    required SpecForgeController controller,
    required FunctionalDomain domain,
  }) => showDialog<DomainIterationSnapshot>(
    context: context,
    builder: (_) =>
        CreateIterationSnapshotDialog(controller: controller, domain: domain),
  );

  @override
  State<CreateIterationSnapshotDialog> createState() =>
      _CreateIterationSnapshotDialogState();
}

class _CreateIterationSnapshotDialogState
    extends State<CreateIterationSnapshotDialog> {
  late final int _nextIterationNumber;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _notesCtrl;
  bool _activateAsBaseline = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nextIterationNumber =
        widget.domain.iterationSnapshots
            .map((s) => s.iterationNumber)
            .fold<int>(0, (a, b) => a > b ? a : b) +
        1;
    _labelCtrl = TextEditingController(text: 'Itération $_nextIterationNumber');
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  ({int models, int valueObjects, int useCases, int sagas})
  _computePreviewCounts() {
    var modelCount = 0;
    final contracts = widget.domain.contracts;
    if (contracts != null) {
      for (final group in contracts.groups) {
        modelCount += group.children.length;
      }
    }
    final voCount = widget.controller.domainCatalog
        .resolvedValueObjectsForDomain(widget.domain.id)
        .length;
    final orchestration = widget.domain.useCaseOrchestration;
    final ucCount = orchestration?.useCases.length ?? 0;
    final sagaCount = orchestration?.sagas.length ?? 0;
    return (
      models: modelCount,
      valueObjects: voCount,
      useCases: ucCount,
      sagas: sagaCount,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final cleanLabel = _labelCtrl.text.trim();
    final cleanNotes = _notesCtrl.text.trim();
    if (cleanLabel.isEmpty || cleanLabel.length > 120) {
      setState(() {
        _error = 'Le libellé du jalon doit contenir entre 1 et 120 caractères.';
      });
      return;
    }
    if (cleanNotes.length > 2000) {
      setState(() {
        _error = 'Les notes du jalon ne peuvent pas dépasser 2000 caractères.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final snapshot = await widget.controller.createDomainIterationSnapshot(
        widget.domain.id,
        label: cleanLabel,
        notes: cleanNotes,
        activateAsBaseline: _activateAsBaseline,
      );
      if (!mounted) return;
      Navigator.pop(context, snapshot);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final counts = _computePreviewCounts();
    final previewSummary =
        '${counts.models} modèles/contrats, '
        '${counts.valueObjects} Value Objects, '
        '${counts.useCases} Use Cases, '
        '${counts.sagas} Sagas';

    return AlertDialog(
      title: Row(
        spacing: 10,
        children: [
          Icon(Icons.bookmark_add_rounded, color: colors.primary),
          Expanded(
            child: Text(
              'Figer un jalon d’itération — ${widget.domain.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Container(
                key: const ValueKey('create-snapshot-preview'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(
                      'Périmètre capturé (Itération #$_nextIterationNumber)',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      previewSummary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Container(
                  key: const ValueKey('create-snapshot-error'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              TextField(
                key: const ValueKey('create-snapshot-label-field'),
                controller: _labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Libellé du jalon *',
                  hintText: 'Ex. Itération 1 — Socle MVP Facturation',
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                key: const ValueKey('create-snapshot-notes-field'),
                controller: _notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes de livraison / périmètre (optionnel)',
                  hintText: 'Ex. Périmètre livré en sprint 3, contrats validés avec le BFF…',
                  border: OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('create-snapshot-activate-checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _activateAsBaseline,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _activateAsBaseline = v ?? true),
                title: const Text('Définir comme jalon de référence actif'),
                subtitle: const Text(
                  'Active immédiatement la détection de dérive par rapport à ce jalon.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('create-snapshot-cancel-btn'),
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('create-snapshot-submit-btn'),
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.bookmark_added_rounded, size: 18),
          label: const Text('Figer le jalon'),
        ),
      ],
    );
  }
}

/// Dialogue modal de consultation, d'activation/désactivation et de suppression
/// de l'historique des [DomainIterationSnapshot] d'un domaine fonctionnel.
class ManageIterationSnapshotsDialog extends StatefulWidget {
  /// Crée le dialogue de gestion des jalons d'itération du domaine [domainId].
  const ManageIterationSnapshotsDialog({
    required this.controller,
    required this.domainId,
    super.key,
  });

  /// Contrôleur exposant et persistant les jalons du domaine.
  final SpecForgeController controller;

  /// Identifiant du domaine fonctionnel inspecté.
  final String domainId;

  /// Ouvre le dialogue modal de gestion de l'historique des jalons.
  static Future<void> show(
    BuildContext context, {
    required SpecForgeController controller,
    required String domainId,
  }) => showDialog<void>(
    context: context,
    builder: (_) => ManageIterationSnapshotsDialog(
      controller: controller,
      domainId: domainId,
    ),
  );

  @override
  State<ManageIterationSnapshotsDialog> createState() =>
      _ManageIterationSnapshotsDialogState();
}

class _ManageIterationSnapshotsDialogState
    extends State<ManageIterationSnapshotsDialog> {
  Future<void> _confirmDeleteSnapshot(
    FunctionalDomain domain,
    DomainIterationSnapshot snapshot,
  ) async {
    final isActive = domain.activeBaselineSnapshotId == snapshot.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Supprimer « ${snapshot.label} » ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              'Le jalon Itération #${snapshot.iterationNumber} '
              '(« ${snapshot.label} ») sera définitivement retiré de '
              'l’historique du domaine « ${domain.name} ».',
            ),
            if (isActive)
              Text(
                'Ce jalon est actuellement la référence active : la baseline '
                'basculera automatiquement sur le dernier jalon restant (ou '
                'sera désactivée s’il n’en reste aucun).',
                style: TextStyle(
                  color: Theme.of(dialogCtx).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('manage-snapshot-confirm-delete-btn'),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.deleteDomainIterationSnapshot(
      domain.id,
      snapshot.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final domain = widget.controller.domainCatalog.domains
            .where((d) => d.id == widget.domainId)
            .firstOrNull;

        if (domain == null) {
          return AlertDialog(
            title: const Text('Historique des jalons'),
            content: const Text('Ce domaine n’existe plus.'),
            actions: [
              TextButton(
                key: const ValueKey('manage-snapshots-close-btn'),
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          );
        }

        final snapshots = _sortedSnapshotsNewestFirst(
          domain.iterationSnapshots,
        );
        final activeId = domain.activeBaselineSnapshotId;
        final activePalette = _paletteForState(
          ArtifactEvolutionState.unchanged,
          SemVerBump.none,
          colors,
        );

        return AlertDialog(
          insetPadding: const EdgeInsets.all(20),
          title: Row(
            spacing: 10,
            children: [
              Icon(Icons.history_rounded, color: colors.primary),
              Expanded(
                child: Text(
                  'Historique des jalons — ${domain.name} (${snapshots.length})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('manage-snapshots-create-btn'),
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text('Figer un jalon…'),
                onPressed: () => CreateIterationSnapshotDialog.show(
                  context,
                  controller: widget.controller,
                  domain: domain,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: (screen.width * 0.68).clamp(560.0, 820.0),
            height: (screen.height * 0.68).clamp(360.0, 620.0),
            child: snapshots.isEmpty
                ? Center(
                    child: Text(
                      'Aucun jalon d’itération n’a encore été capturé pour ce domaine.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: snapshots.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final snap = snapshots[index];
                      final isActive = snap.id == activeId;
                      final countsLabel =
                          '${snap.models.length} modèle(s) · '
                          '${snap.valueObjects.length} VO · '
                          '${snap.useCases.length} UC · '
                          '${snap.sagas.length} Saga(s)';

                      return Container(
                        key: ValueKey('manage-snapshot-card-${snap.id}'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? colors.secondaryContainer.withValues(
                                  alpha: 0.35,
                                )
                              : colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isActive
                                ? colors.primary.withValues(alpha: 0.55)
                                : colors.outlineVariant,
                            width: isActive ? 1.4 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Row(
                              spacing: 8,
                              children: [
                                _buildStyledPill(
                                  label: 'Itération #${snap.iterationNumber}',
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  foregroundColor: colors.onSurface,
                                  borderColor: colors.outlineVariant,
                                  compact: true,
                                ),
                                Expanded(
                                  child: Text(
                                    snap.label,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive)
                                  _buildStyledPill(
                                    key: ValueKey(
                                      'manage-snapshot-active-badge-${snap.id}',
                                    ),
                                    label: 'Jalon actif',
                                    icon: Icons.check_circle_rounded,
                                    backgroundColor: activePalette.bg,
                                    foregroundColor: activePalette.fg,
                                    borderColor: activePalette.border,
                                    compact: true,
                                  ),
                              ],
                            ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Tooltip(
                                  message: _formatDateTimeUtc(snap.createdAt),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 4,
                                    children: [
                                      Icon(
                                        Icons.schedule_rounded,
                                        size: 14,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      Text(
                                        _formatDateTimeLocal(snap.createdAt),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  countsLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (snap.notes.trim().isNotEmpty)
                              Text(
                                snap.notes.trim(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurface,
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              spacing: 8,
                              children: [
                                if (isActive)
                                  OutlinedButton(
                                    key: ValueKey(
                                      'manage-snapshot-toggle-${snap.id}',
                                    ),
                                    onPressed: () => widget.controller
                                        .setActiveBaselineSnapshot(
                                          domain.id,
                                          null,
                                        ),
                                    child: const Text('Désactiver'),
                                  )
                                else
                                  FilledButton.tonal(
                                    key: ValueKey(
                                      'manage-snapshot-toggle-${snap.id}',
                                    ),
                                    onPressed: () => widget.controller
                                        .setActiveBaselineSnapshot(
                                          domain.id,
                                          snap.id,
                                        ),
                                    child: const Text(
                                      'Activer comme référence',
                                    ),
                                  ),
                                IconButton(
                                  key: ValueKey(
                                    'manage-snapshot-delete-${snap.id}',
                                  ),
                                  tooltip: 'Supprimer ce jalon',
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: colors.error,
                                  ),
                                  onPressed: () =>
                                      _confirmDeleteSnapshot(domain, snap),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('manage-snapshots-close-btn'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }
}

/// Dialogue modal détaillant le diff structuré `vN → vN+1` d'un artefact Design
/// ([ArtifactEvolutionReport]), ses impacts transitifs amont et l'action 1-clic
/// d'application de la version SemVer recommandée.
class ArtifactEvolutionDiffDialog extends StatelessWidget {
  /// Crée la visionneuse de diff d'un artefact Design.
  const ArtifactEvolutionDiffDialog({
    required this.report,
    this.baselineLabel,
    this.onApplyRecommendedVersion,
    super.key,
  });

  /// Rapport complet d'évolution de l'artefact inspecté.
  final ArtifactEvolutionReport report;

  /// Libellé optionnel du jalon de référence comparé.
  final String? baselineLabel;

  /// Callback optionnel permettant d'appliquer directement `report.recommendedVersion`.
  final ValueChanged<String>? onApplyRecommendedVersion;

  /// Ouvre le dialogue de diff structuré pour [report].
  static Future<void> show(
    BuildContext context, {
    required ArtifactEvolutionReport report,
    String? baselineLabel,
    ValueChanged<String>? onApplyRecommendedVersion,
  }) => showDialog<void>(
    context: context,
    builder: (_) => ArtifactEvolutionDiffDialog(
      report: report,
      baselineLabel: baselineLabel,
      onApplyRecommendedVersion: onApplyRecommendedVersion,
    ),
  );

  Map<String, List<ArtifactChangeEntry>> _groupedDirectChanges() {
    final grouped = <String, List<ArtifactChangeEntry>>{};
    for (final entry in report.directChanges) {
      final cat = entry.category.trim().isEmpty ? 'Général' : entry.category;
      (grouped[cat] ??= <ArtifactChangeEntry>[]).add(entry);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statePalette = _paletteForState(
      report.state,
      report.effectiveBump,
      colors,
    );
    final bumpPalette = _paletteForSemVerBump(report.effectiveBump, colors);
    final groupedChanges = _groupedDirectChanges();
    final canApplyBump =
        report.needsVersionBump && onApplyRecommendedVersion != null;

    return AlertDialog(
      insetPadding: const EdgeInsets.all(20),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStyledPill(
                label: report.kind.label,
                icon: _iconForArtifactKind(report.kind),
                backgroundColor: colors.surfaceContainerHighest,
                foregroundColor: colors.onSurface,
                borderColor: colors.outlineVariant,
                compact: true,
              ),
              if (report.valueObjectScope == ValueObjectScope.shared)
                _buildStyledPill(
                  label: 'Shared Kernel',
                  backgroundColor: colors.tertiaryContainer,
                  foregroundColor: colors.onTertiaryContainer,
                  borderColor: colors.tertiary.withValues(alpha: 0.35),
                  compact: true,
                ),
              Text(
                report.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              _buildStyledPill(
                key: const ValueKey('artifact-diff-version-range'),
                label:
                    'v${report.baselineVersion ?? '—'} → v${report.currentVersion}',
                backgroundColor: colors.surfaceContainer,
                foregroundColor: colors.onSurfaceVariant,
                borderColor: colors.outlineVariant,
                compact: true,
              ),
              _buildStyledPill(
                key: const ValueKey('artifact-diff-state-badge'),
                label: report.state.label,
                backgroundColor: statePalette.bg,
                foregroundColor: statePalette.fg,
                borderColor: statePalette.border,
                compact: true,
              ),
              if (report.effectiveBump.hasChange)
                _buildStyledPill(
                  key: const ValueKey('artifact-diff-semver-badge'),
                  label: 'SemVer : ${report.effectiveBump.label}',
                  backgroundColor: bumpPalette.bg,
                  foregroundColor: bumpPalette.fg,
                  borderColor: bumpPalette.border,
                  compact: true,
                ),
            ],
          ),
          if (report.subtitle.trim().isNotEmpty ||
              (baselineLabel != null && baselineLabel!.trim().isNotEmpty))
            Text(
              [
                if (report.subtitle.trim().isNotEmpty) report.subtitle.trim(),
                if (baselineLabel != null && baselineLabel!.trim().isNotEmpty)
                  'Jalon : ${baselineLabel!.trim()}',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: (screen.width * 0.68).clamp(540.0, 820.0),
        height: (screen.height * 0.66).clamp(320.0, 580.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              if (groupedChanges.isNotEmpty) ...[
                Text(
                  'Modifications directes (${report.directChanges.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final group in groupedChanges.entries)
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(9),
                            ),
                          ),
                          child: Text(
                            '${group.key} (${group.value.length})',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (var i = 0; i < group.value.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          _buildDirectChangeRow(
                            context,
                            group.value[i],
                            colors,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
              if (report.impactedBy.isNotEmpty)
                Container(
                  key: const ValueKey('artifact-diff-impacted-section'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Row(
                        spacing: 6,
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            size: 16,
                            color: colors.primary,
                          ),
                          Text(
                            'Dépendances amont ayant propagé un impact (${report.impactedBy.length})',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      for (final cause in report.impactedBy)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Text(
                              '⇄',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                cause,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (groupedChanges.isEmpty && report.impactedBy.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Text(
                    switch (report.state) {
                      ArtifactEvolutionState.added => 'Cet artefact a été créé après la capture du jalon de référence.',
                      ArtifactEvolutionState.removed => 'Cet artefact figurait dans le jalon de référence mais a été supprimé du domaine.',
                      ArtifactEvolutionState.unchanged => 'Aucune différence structurelle ou documentaire détectée depuis le jalon.',
                      ArtifactEvolutionState.noBaseline =>
                        'Aucun jalon de référence n’est actif sur ce domaine.',
                      ArtifactEvolutionState.modified ||
                      ArtifactEvolutionState.impacted =>
                        'Évolution détectée par rapport au jalon de référence.',
                    },
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (canApplyBump)
          FilledButton.icon(
            key: const ValueKey('artifact-diff-apply-version-btn'),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: Text('Appliquer v${report.recommendedVersion}'),
            onPressed: () {
              onApplyRecommendedVersion!(report.recommendedVersion);
              Navigator.pop(context);
            },
          ),
        TextButton(
          key: const ValueKey('artifact-diff-close-btn'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _buildDirectChangeRow(
    BuildContext context,
    ArtifactChangeEntry entry,
    ColorScheme colors,
  ) {
    final classified = _classifyChangeEntry(entry, colors);
    final unitBumpPalette = _paletteForSemVerBump(entry.impact, colors);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 10,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: classified.bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: classified.border),
            ),
            child: Text(
              classified.symbol,
              style: TextStyle(
                color: classified.fg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              classified.text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          _buildStyledPill(
            label: entry.impact.shortLabel,
            backgroundColor: unitBumpPalette.bg,
            foregroundColor: unitBumpPalette.fg,
            borderColor: unitBumpPalette.border,
            compact: true,
          ),
        ],
      ),
    );
  }
}

/// Vue d'ensemble modale de tous les artefacts ajoutés, modifiés, impactés ou
/// supprimés sur un [FunctionalDomain] depuis son jalon actif, avec application
/// SemVer unitaire ou globale en un clic.
class DomainEvolutionSummaryDialog extends StatefulWidget {
  /// Crée le dialogue récapitulatif d'évolution de [domain].
  const DomainEvolutionSummaryDialog({
    required this.controller,
    required this.domain,
    this.report,
    super.key,
  });

  /// Contrôleur orchestrant les incréments de version et l'analyse du domaine.
  final SpecForgeController controller;

  /// Domaine fonctionnel inspecté.
  final FunctionalDomain domain;

  /// Rapport initial optionnel ; s'il est omis ou après mutation du catalogue,
  /// l'analyse est recalculée en direct.
  final DomainEvolutionReport? report;

  /// Ouvre la vue modale de synthèse d'évolution du domaine.
  static Future<void> show(
    BuildContext context, {
    required SpecForgeController controller,
    required FunctionalDomain domain,
    DomainEvolutionReport? report,
  }) => showDialog<void>(
    context: context,
    builder: (_) => DomainEvolutionSummaryDialog(
      controller: controller,
      domain: domain,
      report: report,
    ),
  );

  @override
  State<DomainEvolutionSummaryDialog> createState() =>
      _DomainEvolutionSummaryDialogState();
}

class _DomainEvolutionSummaryDialogState
    extends State<DomainEvolutionSummaryDialog> {
  late final DomainCatalog _initialCatalog;
  ArtifactEvolutionState? _stateFilter;
  bool _applyingAll = false;

  @override
  void initState() {
    super.initState();
    _initialCatalog = widget.controller.domainCatalog;
  }

  Future<void> _applySingleBump(
    String domainId,
    ArtifactEvolutionReport item,
    String targetVersion,
  ) async {
    await widget.controller.applyDesignArtifactVersionBump(
      domainId: domainId,
      kind: item.kind,
      artifactId: item.id,
      newVersion: targetVersion,
      valueObjectScope: item.valueObjectScope,
    );
  }

  Future<void> _applyAllBumps(
    String domainId,
    List<ArtifactEvolutionReport> bumpableItems,
  ) async {
    if (_applyingAll || bumpableItems.isEmpty) return;
    setState(() => _applyingAll = true);
    try {
      for (final item in bumpableItems) {
        await widget.controller.applyDesignArtifactVersionBump(
          domainId: domainId,
          kind: item.kind,
          artifactId: item.id,
          newVersion: item.recommendedVersion,
          valueObjectScope: item.valueObjectScope,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _applyingAll = false);
      }
    }
  }

  List<ArtifactEvolutionReport> _collectDisplayItems(
    DomainEvolutionReport report,
  ) {
    final items = <ArtifactEvolutionReport>[
      ...report.allCurrentReports.where(
        (r) => r.state == ArtifactEvolutionState.modified,
      ),
      ...report.allCurrentReports.where(
        (r) => r.state == ArtifactEvolutionState.impacted,
      ),
      ...report.allCurrentReports.where(
        (r) => r.state == ArtifactEvolutionState.added,
      ),
      ...report.removedArtifacts,
    ];
    if (_stateFilter == null) return items;
    return items.where((r) => r.state == _stateFilter).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final currentCatalog = widget.controller.domainCatalog;
        final liveDomain =
            currentCatalog.domains
                .where((d) => d.id == widget.domain.id)
                .firstOrNull ??
            widget.domain;
        final liveReport =
            (widget.report != null &&
                identical(currentCatalog, _initialCatalog))
            ? widget.report!
            : widget.controller.analyzeDomainEvolution(
                liveDomain.id,
                baselineOverride: widget.report?.baseline,
              );

        final baseline = liveReport.baseline;
        final baselineSummary = baseline == null
            ? 'Aucun jalon actif'
            : '${baseline.label} (Itération #${baseline.iterationNumber} · '
                  '${_formatDateShort(baseline.createdAt)})';

        final bumpableItems = liveReport.allCurrentReports
            .where((r) => r.needsVersionBump)
            .toList(growable: false);
        final visibleItems = _collectDisplayItems(liveReport);
        final totalChanged =
            liveReport.totalActionableCount + liveReport.removedCount;

        return AlertDialog(
          insetPadding: const EdgeInsets.all(20),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Row(
                spacing: 10,
                children: [
                  Icon(Icons.compare_arrows_rounded, color: colors.primary),
                  Expanded(
                    child: Text(
                      'Synthèse d’évolution — ${liveDomain.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Text(
                'Référence : $baselineSummary',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: (screen.width * 0.74).clamp(620.0, 940.0),
            height: (screen.height * 0.72).clamp(400.0, 660.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('domain-evolution-filter-all'),
                      label: Text('Tous ($totalChanged)'),
                      selected: _stateFilter == null,
                      onSelected: (_) => setState(() => _stateFilter = null),
                    ),
                    ChoiceChip(
                      key: const ValueKey('domain-evolution-filter-modified'),
                      label: Text('Δ Modifiés (${liveReport.modifiedCount})'),
                      selected: _stateFilter == ArtifactEvolutionState.modified,
                      onSelected: (_) => setState(
                        () => _stateFilter = ArtifactEvolutionState.modified,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('domain-evolution-filter-impacted'),
                      label: Text('⇄ Impactés (${liveReport.impactedCount})'),
                      selected: _stateFilter == ArtifactEvolutionState.impacted,
                      onSelected: (_) => setState(
                        () => _stateFilter = ArtifactEvolutionState.impacted,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('domain-evolution-filter-added'),
                      label: Text('+ Nouveaux (${liveReport.addedCount})'),
                      selected: _stateFilter == ArtifactEvolutionState.added,
                      onSelected: (_) => setState(
                        () => _stateFilter = ArtifactEvolutionState.added,
                      ),
                    ),
                    ChoiceChip(
                      key: const ValueKey('domain-evolution-filter-removed'),
                      label: Text('- Supprimés (${liveReport.removedCount})'),
                      selected: _stateFilter == ArtifactEvolutionState.removed,
                      onSelected: (_) => setState(
                        () => _stateFilter = ArtifactEvolutionState.removed,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: visibleItems.isEmpty
                      ? Center(
                          child: Text(
                            totalChanged == 0
                                ? 'Tous les artefacts du domaine sont conformes au jalon de référence.'
                                : 'Aucun artefact ne correspond au filtre sélectionné.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: visibleItems.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) {
                            final item = visibleItems[index];
                            return _buildSummaryRow(
                              context,
                              domain: liveDomain,
                              baselineLabel: baseline?.label,
                              item: item,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            if (bumpableItems.isNotEmpty)
              Tooltip(
                message:
                    'Appliquer la version SemVer suggérée sur '
                    '${bumpableItems.length} artefact(s) en attente.',
                child: FilledButton.icon(
                  key: const ValueKey('domain-evolution-bump-all-btn'),
                  onPressed: _applyingAll
                      ? null
                      : () => _applyAllBumps(liveDomain.id, bumpableItems),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('Tout bumper (SemVer suggéré)'),
                ),
              ),
            TextButton(
              key: const ValueKey('domain-evolution-close-btn'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(
    BuildContext context, {
    required FunctionalDomain domain,
    required String? baselineLabel,
    required ArtifactEvolutionReport item,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Future<void> openDiff() => ArtifactEvolutionDiffDialog.show(
      context,
      report: item,
      baselineLabel: baselineLabel,
      onApplyRecommendedVersion: item.state == ArtifactEvolutionState.removed
          ? null
          : (ver) => _applySingleBump(domain.id, item, ver),
    );

    final detailLine = switch (item.state) {
      ArtifactEvolutionState.modified =>
        '${item.directChanges.length} changement(s) direct(s)'
            '${item.impactedBy.isEmpty ? '' : ' · ${item.impactedBy.length} impact(s) amont'}',
      ArtifactEvolutionState.impacted => item.impactedBy.join(' · '),
      ArtifactEvolutionState.added => 'Nouvel artefact ajouté depuis le jalon',
      ArtifactEvolutionState.removed =>
        'Présent dans le jalon (v${item.baselineVersion ?? item.currentVersion}), supprimé du domaine',
      ArtifactEvolutionState.unchanged ||
      ArtifactEvolutionState.noBaseline => '',
    };

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('domain-evolution-row-${item.kind.name}-${item.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: openDiff,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            spacing: 10,
            children: [
              Icon(
                _iconForArtifactKind(item.kind),
                size: 18,
                color: colors.primary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _buildStyledPill(
                          label: item.kind.shortLabel,
                          backgroundColor: colors.surfaceContainerHighest,
                          foregroundColor: colors.onSurfaceVariant,
                          borderColor: colors.outlineVariant,
                          compact: true,
                        ),
                        if (item.valueObjectScope == ValueObjectScope.shared)
                          _buildStyledPill(
                            label: 'Shared Kernel',
                            backgroundColor: colors.tertiaryContainer,
                            foregroundColor: colors.onTertiaryContainer,
                            borderColor: colors.tertiary.withValues(
                              alpha: 0.35,
                            ),
                            compact: true,
                          ),
                        Text(
                          'v${item.baselineVersion ?? '—'} → v${item.currentVersion}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        EvolutionDriftBadge(report: item, compact: true),
                      ],
                    ),
                    if (detailLine.isNotEmpty)
                      Text(
                        detailLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (item.needsVersionBump)
                SemVerBumpActionChip(
                  key: ValueKey(
                    'domain-evolution-bump-${item.kind.name}-${item.id}',
                  ),
                  report: item,
                  compact: true,
                  onApplyVersion: (ver) =>
                      _applySingleBump(domain.id, item, ver),
                ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
