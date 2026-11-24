/// Colonne chronologique visuelle d'une étape Event Storming DSL v1.0
/// ([EventStormStepColumn]) avec palette officielle des post-its
/// (Read Model vert, Acteur petit jaune, Politique violet, Commande bleue,
/// Agrégat grand jaune, Système externe rose pâle, Événement/Outcomes orange,
/// Hotspot rose vif).
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/event_storming_spec.dart';

/// Palette de couleurs fidèle aux post-its Event Storming DSL v1.0.
class EventStormPostItColors {
  /// Construit une paire de couleurs (fond, bordure, texte, badge).
  const EventStormPostItColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.badgeBackground,
  });

  /// Couleur de fond du post-it.
  final Color background;

  /// Couleur de bordure.
  final Color border;

  /// Couleur de texte principal.
  final Color foreground;

  /// Couleur de fond du badge de type.
  final Color badgeBackground;

  /// Vert — Read Model (`read_model`).
  static EventStormPostItColors readModel(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF18301B),
          border: Color(0xFF66BB6A),
          foreground: Color(0xFFC8E6C9),
          badgeBackground: Color(0xFF2E7D32),
        )
      : const EventStormPostItColors(
          background: Color(0xFFE8F5E9),
          border: Color(0xFF43A047),
          foreground: Color(0xFF1B5E20),
          badgeBackground: Color(0xFFC8E6C9),
        );

  /// Petit Jaune — Acteur (`actor`).
  static EventStormPostItColors actor(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF332D10),
          border: Color(0xFFFDD835),
          foreground: Color(0xFFFFF9C4),
          badgeBackground: Color(0xFF9E8408),
        )
      : const EventStormPostItColors(
          background: Color(0xFFFFFDE7),
          border: Color(0xFFFBC02D),
          foreground: Color(0xFF5D4037),
          badgeBackground: Color(0xFFFFF59D),
        );

  /// Violet — Politique réactive (`policy`).
  static EventStormPostItColors policy(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF2D1936),
          border: Color(0xFFBA68C8),
          foreground: Color(0xFFF3E5F5),
          badgeBackground: Color(0xFF6A1B9A),
        )
      : const EventStormPostItColors(
          background: Color(0xFFF3E5F5),
          border: Color(0xFF8E24AA),
          foreground: Color(0xFF4A148C),
          badgeBackground: Color(0xFFE1BEE7),
        );

  /// Bleu — Commande (`command`).
  static EventStormPostItColors command(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF142840),
          border: Color(0xFF42A5F5),
          foreground: Color(0xFFE3F2FD),
          badgeBackground: Color(0xFF1565C0),
        )
      : const EventStormPostItColors(
          background: Color(0xFFE3F2FD),
          border: Color(0xFF1E88E5),
          foreground: Color(0xFF0D47A1),
          badgeBackground: Color(0xFFBBDEFB),
        );

  /// Grand Jaune / Ambre — Agrégat (`aggregate`).
  static EventStormPostItColors aggregate(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF362812),
          border: Color(0xFFFFCA28),
          foreground: Color(0xFFFFECB3),
          badgeBackground: Color(0xFFA67400),
        )
      : const EventStormPostItColors(
          background: Color(0xFFFFF8E1),
          border: Color(0xFFFFB300),
          foreground: Color(0xFF5D4037),
          badgeBackground: Color(0xFFFFE082),
        );

  /// Rose pâle — Système externe (`external_system`).
  static EventStormPostItColors externalSystem(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF381A27),
          border: Color(0xFFF48FB1),
          foreground: Color(0xFFFCE4EC),
          badgeBackground: Color(0xFF880E4F),
        )
      : const EventStormPostItColors(
          background: Color(0xFFFCE4EC),
          border: Color(0xFFEC407A),
          foreground: Color(0xFF880E4F),
          badgeBackground: Color(0xFFF8BBD0),
        );

  /// Orange — Événement domaine (`domain_event`).
  static EventStormPostItColors domainEvent(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF3D2612),
          border: Color(0xFFFF9800),
          foreground: Color(0xFFFFE0B2),
          badgeBackground: Color(0xFFAD5800),
        )
      : const EventStormPostItColors(
          background: Color(0xFFFFF3E0),
          border: Color(0xFFFB8C00),
          foreground: Color(0xFF5D2F00),
          badgeBackground: Color(0xFFFFCC80),
        );

  /// Orange foncé / Erreur — Branche d'outcome `is_error: true`.
  static EventStormPostItColors errorOutcome(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF3B1A16),
          border: Color(0xFFFF7043),
          foreground: Color(0xFFFFCCBC),
          badgeBackground: Color(0xFFBF360C),
        )
      : const EventStormPostItColors(
          background: Color(0xFFFBE9E7),
          border: Color(0xFFE64A19),
          foreground: Color(0xFFBF360C),
          badgeBackground: Color(0xFFFFCCBC),
        );

  /// Rose vif — Hotspot (`hotspots[]`).
  static EventStormPostItColors hotspot(bool isDark) => isDark
      ? const EventStormPostItColors(
          background: Color(0xFF421024),
          border: Color(0xFFF06292),
          foreground: Color(0xFFFCE4EC),
          badgeBackground: Color(0xFFC2185B),
        )
      : const EventStormPostItColors(
          background: Color(0xFFFCE4EC),
          border: Color(0xFFD81B60),
          foreground: Color(0xFF880E4F),
          badgeBackground: Color(0xFFF48FB1),
        );
}

/// Colonne visuelle représentant une [EventStormStep] sur la frise chronologique.
class EventStormStepColumn extends StatelessWidget {
  /// Construit la colonne pour [step] dans [document].
  const EventStormStepColumn({
    required this.document,
    required this.step,
    required this.isFocused,
    required this.isDark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onMoveLeft,
    this.onMoveRight,
    this.onPromotePolicy,
    this.onToggleHotspotStatus,
    super.key,
  });

  /// Document parent (pour résoudre les libellés du catalogue).
  final EventStormDocument document;

  /// Étape chronologique affichée.
  final EventStormStep step;

  /// Indique si cette étape est sélectionnée.
  final bool isFocused;

  /// Indique si le thème courant est sombre.
  final bool isDark;

  /// Sélectionne cette étape dans le contrôleur.
  final VoidCallback onTap;

  /// Ouvre le dialogue d'édition de l'étape.
  final VoidCallback onEdit;

  /// Supprime cette étape.
  final VoidCallback onDelete;

  /// Déplace cette étape vers la gauche (si non première).
  final VoidCallback? onMoveLeft;

  /// Déplace cette étape vers la droite (si non dernière).
  final VoidCallback? onMoveRight;

  /// Promeut la `policy` de cette étape en règle de gestion `RG-xxx`.
  final VoidCallback? onPromotePolicy;

  /// Bascule le statut `open` / `resolved` d'un hotspot de cette étape.
  final ValueChanged<EventStormHotspot>? onToggleHotspotStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final actorItem = step.actor.isEmpty
        ? null
        : document.catalog.findActor(step.actor);
    final aggItem = step.aggregate.isEmpty
        ? null
        : document.catalog.findAggregate(step.aggregate);
    final extItem = step.externalSystem.isEmpty
        ? null
        : document.catalog.findExternalSystem(step.externalSystem);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 312,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused ? colors.primary : colors.outlineVariant,
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête de la colonne : Step N + Backlog + actions
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: isFocused
                    ? colors.primaryContainer.withValues(alpha: 0.45)
                    : colors.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Step ${step.step}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (step.backlog != null && step.backlog!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          if (step.backlog!.epic.isNotEmpty)
                            step.backlog!.epic,
                          if (step.backlog!.story.isNotEmpty)
                            step.backlog!.story,
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (onMoveLeft != null)
                    IconButton(
                      tooltip: 'Déplacer à gauche',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      onPressed: onMoveLeft,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                  if (onMoveRight != null)
                    IconButton(
                      tooltip: 'Déplacer à droite',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 26,
                        minHeight: 26,
                      ),
                      onPressed: onMoveRight,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  IconButton(
                    tooltip: 'Modifier l’étape',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Supprimer l’étape',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),

            // Contenu empilé des post-its
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  if (step.triggeredBy != null)
                    _TriggerBanner(trigger: step.triggeredBy!),

                  if (step.readModel != null)
                    _PostItBox(
                      badge: 'READ MODEL',
                      title: step.readModel!.name,
                      palette: EventStormPostItColors.readModel(isDark),
                      chips: [
                        for (final src in step.readModel!.sourceEvents)
                          '← $src',
                        ...step.readModel!.fields,
                      ],
                    ),

                  if (step.actor.isNotEmpty)
                    _PostItBox(
                      badge:
                          'ACTEUR · ${actorItem?.type?.yamlValue ?? 'human'}',
                      code: step.actor,
                      title: actorItem?.name ?? step.actor,
                      palette: EventStormPostItColors.actor(isDark),
                    ),

                  if (step.policy != null)
                    _PostItBox(
                      badge: 'POLITIQUE',
                      title: step.policy!.name,
                      subtitle: step.policy!.rule,
                      palette: EventStormPostItColors.policy(isDark),
                      trailing: onPromotePolicy != null
                          ? TextButton.icon(
                              key: ValueKey(
                                'spec-es-promote-policy-${document.id}-${step.step}',
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                              ),
                              onPressed: onPromotePolicy,
                              icon: const Icon(Icons.gavel_rounded, size: 14),
                              label: const Text(
                                'Promouvoir RG',
                                style: TextStyle(fontSize: 11),
                              ),
                            )
                          : null,
                    ),

                  _PostItBox(
                    badge: 'COMMANDE',
                    title: step.command.name,
                    palette: EventStormPostItColors.command(isDark),
                    chips: step.command.payload,
                  ),

                  if (step.aggregate.isNotEmpty)
                    _PostItBox(
                      badge: 'AGRÉGAT',
                      code: step.aggregate,
                      title: aggItem?.name ?? step.aggregate,
                      palette: EventStormPostItColors.aggregate(isDark),
                    ),

                  if (step.externalSystem.isNotEmpty)
                    _PostItBox(
                      badge: 'SYSTÈME EXTERNE',
                      code: step.externalSystem,
                      title: extItem?.name ?? step.externalSystem,
                      palette: EventStormPostItColors.externalSystem(isDark),
                    ),

                  if (step.domainEvent != null)
                    _PostItBox(
                      badge: 'ÉVÉNEMENT',
                      code: step.domainEvent!.id,
                      title: step.domainEvent!.name,
                      palette: EventStormPostItColors.domainEvent(isDark),
                      chips: step.domainEvent!.data,
                    )
                  else if (step.outcomes.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 6,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.call_split_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Embranchement OU exclusif (${step.outcomes.length})',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        for (final outcome in step.outcomes)
                          _PostItBox(
                            badge: outcome.isError
                                ? 'OUTCOME · ERREUR'
                                : 'OUTCOME · SUCCÈS',
                            code: outcome.domainEvent.id,
                            title: outcome.domainEvent.name,
                            subtitle: 'Si : ${outcome.condition}',
                            palette: outcome.isError
                                ? EventStormPostItColors.errorOutcome(isDark)
                                : EventStormPostItColors.domainEvent(isDark),
                            chips: outcome.domainEvent.data,
                          ),
                      ],
                    ),

                  if (step.hotspots.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 6,
                      children: [
                        for (final hs in step.hotspots)
                          _PostItBox(
                            badge:
                                'HOTSPOT · ${hs.severity.yamlValue.toUpperCase()} · ${hs.isResolved ? 'RÉSOLU' : 'OUVERT'}',
                            code: hs.id,
                            title: hs.question,
                            subtitle: hs.owner.isEmpty
                                ? null
                                : 'Owner : ${hs.owner}',
                            palette: EventStormPostItColors.hotspot(isDark),
                            trailing: onToggleHotspotStatus != null
                                ? IconButton(
                                    tooltip: hs.isResolved
                                        ? 'Rouvrir ce hotspot'
                                        : 'Marquer comme résolu',
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 16,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 24,
                                      minHeight: 24,
                                    ),
                                    onPressed: () => onToggleHotspotStatus!(hs),
                                    icon: Icon(
                                      hs.isResolved
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                    ),
                                  )
                                : null,
                          ),
                      ],
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

class _TriggerBanner extends StatelessWidget {
  const _TriggerBanner({required this.trigger});

  final EventStormTrigger trigger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, label, accent) = switch (trigger.mode) {
      EventStormTriggerMode.single => (
        Icons.subdirectory_arrow_right_rounded,
        'Déclenché par : ${trigger.eventIds.first}',
        colors.primary,
      ),
      EventStormTriggerMode.allOf => (
        Icons.merge_rounded,
        'Sync ET (all_of) : ${trigger.eventIds.join(' + ')}',
        Colors.deepPurple,
      ),
      EventStormTriggerMode.anyOf => (
        Icons.call_merge_rounded,
        'Convergence OU (any_of) : ${trigger.eventIds.join(' | ')}',
        Colors.teal,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostItBox extends StatelessWidget {
  const _PostItBox({
    required this.badge,
    required this.title,
    required this.palette,
    this.code,
    this.subtitle,
    this.chips = const <String>[],
    this.trailing,
  });

  final String badge;
  final String? code;
  final String title;
  final String? subtitle;
  final EventStormPostItColors palette;
  final List<String> chips;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: palette.badgeBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: palette.foreground,
                  ),
                ),
              ),
              if (code != null && code!.isNotEmpty)
                Text(
                  code!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: palette.foreground,
                  ),
                ),
              ?trailing,
            ],
          ),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.foreground,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(
              subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: palette.foreground.withValues(alpha: 0.85),
              ),
            ),
          if (chips.isNotEmpty)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final field in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.border.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      field,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: palette.foreground,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
