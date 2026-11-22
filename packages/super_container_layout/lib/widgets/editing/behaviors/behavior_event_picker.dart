/// Sélecteur visuel d'événement déclencheur ([BehaviorEventPicker]) pour le wizard
/// de comportements ([ComponentBehaviorWizard]).
///
/// Organise les [BehaviorEvent] disponibles par catégorie ([BehaviorEventCategory]),
/// met en avant les événements recommandés pour le type de composant ciblé et masque
/// [BehaviorEvent.onCreate] pour les cibles qui ne sont pas des `SuperValue`.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/behaviours/behavior_event.dart';

/// Sélecteur catégorisé permettant à l'utilisateur de choisir un [BehaviorEvent].
class BehaviorEventPicker extends StatelessWidget {
  /// Crée un sélecteur d'événement déclencheur.
  const BehaviorEventPicker({
    required this.selectedEvent,
    required this.onSelected,
    this.componentType,
    this.keyPrefix = 'behavior',
    this.isLayoutTarget = false,
    this.isValueTarget = false,
    super.key,
  });

  /// Événement actuellement sélectionné.
  final BehaviorEvent selectedEvent;

  /// Type du composant ciblé (`'value'`, `'list'`, `'table'`, `'treeView'`,
  /// `'tab'`, `'expansible'`, `'menu'`, `'action'`, `'layout'`, etc.).
  final String? componentType;

  /// Callback invoqué lorsqu'un événement est sélectionné.
  final ValueChanged<BehaviorEvent> onSelected;

  /// Préfixe des clés de test déterministes (`ValueKey('$keyPrefix-event-${event.name}')`).
  final String keyPrefix;

  /// Indique si le composant ciblé est un `SuperLayout`.
  final bool isLayoutTarget;

  /// Indique si le composant ciblé est un `SuperValue`.
  final bool isValueTarget;

  String? get _effectiveComponentType {
    final normalized = componentType?.trim();
    if (normalized != null && normalized.isNotEmpty) return normalized;
    if (isValueTarget) return 'value';
    if (isLayoutTarget) return 'layout';
    return null;
  }

  bool _isVisible(BehaviorEvent event) {
    if (event == BehaviorEvent.onCreate) {
      return isValueTarget || selectedEvent == BehaviorEvent.onCreate;
    }
    return true;
  }

  /// Indique si [event] mérite un badge « Recommandé » pour le composant courant.
  bool _isSpecificallyRecommended(BehaviorEvent event, String? effectiveType) {
    final normalized = (effectiveType ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return event == BehaviorEvent.onTap;
    }
    return switch (normalized) {
      'value' =>
        event == BehaviorEvent.onChanged ||
            event == BehaviorEvent.onSubmitted ||
            event == BehaviorEvent.onFocus ||
            event == BehaviorEvent.onBlur ||
            event == BehaviorEvent.onCreate,
      'listview' ||
      'list' ||
      'table' ||
      'tab' ||
      'tabs' ||
      'bottomnavigationbar' ||
      'navigationrail' ||
      'iterablecontent' => event == BehaviorEvent.onSelected,
      'treeview' || 'tree' =>
        event == BehaviorEvent.onSelected ||
            event == BehaviorEvent.onExpanded ||
            event == BehaviorEvent.onCollapsed,
      'expansible' || 'menu' =>
        event == BehaviorEvent.onExpanded ||
            event == BehaviorEvent.onCollapsed ||
            event == BehaviorEvent.onChanged,
      'layout' =>
        event == BehaviorEvent.onBinding || event == BehaviorEvent.onTap,
      'action' =>
        event == BehaviorEvent.onTap || event == BehaviorEvent.onDoubleTap,
      _ => event == BehaviorEvent.onTap,
    };
  }

  List<BehaviorEventCategory> _orderedCategories(String? effectiveType) {
    final normalized = (effectiveType ?? '').trim().toLowerCase();
    final priority = switch (normalized) {
      'value' => const [
        BehaviorEventCategory.value,
        BehaviorEventCategory.focus,
        BehaviorEventCategory.gesture,
        BehaviorEventCategory.declarative,
      ],
      'listview' ||
      'list' ||
      'table' ||
      'tab' ||
      'tabs' ||
      'bottomnavigationbar' ||
      'navigationrail' ||
      'iterablecontent' => const [
        BehaviorEventCategory.selection,
        BehaviorEventCategory.gesture,
        BehaviorEventCategory.declarative,
      ],
      'treeview' || 'tree' => const [
        BehaviorEventCategory.selection,
        BehaviorEventCategory.disclosure,
        BehaviorEventCategory.gesture,
        BehaviorEventCategory.declarative,
      ],
      'expansible' || 'menu' => const [
        BehaviorEventCategory.disclosure,
        BehaviorEventCategory.value,
        BehaviorEventCategory.gesture,
        BehaviorEventCategory.declarative,
      ],
      'layout' => const [
        BehaviorEventCategory.declarative,
        BehaviorEventCategory.gesture,
        BehaviorEventCategory.pointer,
        BehaviorEventCategory.lifecycle,
      ],
      _ => const [
        BehaviorEventCategory.gesture,
        BehaviorEventCategory.declarative,
        BehaviorEventCategory.pointer,
        BehaviorEventCategory.selection,
        BehaviorEventCategory.value,
      ],
    };

    return [
      ...priority,
      for (final category in BehaviorEventCategory.values)
        if (!priority.contains(category)) category,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final effectiveType = _effectiveComponentType;
    final categories = _orderedCategories(effectiveType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Événement déclencheur',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choisissez quand ce comportement doit se déclencher :',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final category in categories) ...[
          Builder(
            builder: (context) {
              final events = [
                for (final event in BehaviorEvent.values)
                  if (event.category == category && _isVisible(event)) event,
              ];
              if (events.isEmpty) return const SizedBox.shrink();

              final hasRecommended = events.any(
                (e) => _isSpecificallyRecommended(e, effectiveType),
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          category.icon,
                          size: 16,
                          color: hasRecommended
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          category.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: hasRecommended
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        if (hasRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Recommandé',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        final twoColumns = constraints.maxWidth >= 460;
                        final itemWidth = twoColumns
                            ? (constraints.maxWidth - spacing) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final event in events)
                              SizedBox(
                                width: itemWidth,
                                child: _EventCard(
                                  keyPrefix: keyPrefix,
                                  event: event,
                                  selected: event == selectedEvent,
                                  recommended: _isSpecificallyRecommended(
                                    event,
                                    effectiveType,
                                  ),
                                  subdued:
                                      effectiveType != null &&
                                      !event.isRecommendedForComponentType(
                                        effectiveType,
                                      ),
                                  onTap: () => onSelected(event),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.keyPrefix,
    required this.event,
    required this.selected,
    required this.recommended,
    required this.subdued,
    required this.onTap,
  });

  final String keyPrefix;
  final BehaviorEvent event;
  final bool selected;
  final bool recommended;
  final bool subdued;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      key: ValueKey('$keyPrefix-event-${event.name}'),
      margin: EdgeInsets.zero,
      elevation: selected ? 2 : 0,
      color: selected
          ? colors.primaryContainer.withValues(alpha: .35)
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? colors.primary
              : recommended
              ? colors.primary.withValues(alpha: .45)
              : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Opacity(
          opacity: subdued && !selected ? 0.68 : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected ? colors.primary : colors.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary
                        : colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    event.icon,
                    size: 18,
                    color: selected ? colors.onPrimary : colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!event.isImperative)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Déclaratif',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  color: colors.onSecondaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
