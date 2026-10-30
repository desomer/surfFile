import 'package:material_ui/material_ui.dart';

/// Élément de base affiché dans le sélecteur de cible d'un assistant d'édition
/// (Comportements, Données & Liaisons JSON, etc.).
abstract interface class EditorTargetItem {
  String get id;
  String get label;
  IconData? get icon;
  int get depth;
}

/// Liste réutilisable permettant de sélectionner un élément cible dans la
/// hiérarchie (composant courant ou conteneurs parents).
class EditorTargetSelector<T extends EditorTargetItem> extends StatelessWidget {
  const EditorTargetSelector({
    required this.targets,
    required this.selected,
    required this.onSelected,
    this.title = 'Choisir l’élément cible',
    this.subtitle,
    this.itemKeyBuilder,
    this.isSelectedPredicate,
    this.subtitleBuilder,
    this.trailingBuilder,
    super.key,
  });

  final List<T> targets;
  final T selected;
  final ValueChanged<T> onSelected;
  final String title;
  final String? subtitle;
  final Key Function(T target)? itemKeyBuilder;
  final bool Function(T target, T selected)? isSelectedPredicate;
  final Widget Function(BuildContext context, T target)? subtitleBuilder;
  final Widget? Function(BuildContext context, T target)? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final target in targets)
          Builder(
            builder: (context) {
              final isSelected = isSelectedPredicate != null
                  ? isSelectedPredicate!(target, selected)
                  : identical(target, selected) ||
                        (target.id == selected.id &&
                            target.depth == selected.depth);
              final trailing = trailingBuilder?.call(context, target);

              return Card(
                key:
                    itemKeyBuilder?.call(target) ??
                    ValueKey('editor-target-${target.id}-${target.depth}'),
                elevation: isSelected ? 2 : 0,
                color: isSelected
                    ? colors.secondaryContainer.withValues(alpha: .4)
                    : colors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? colors.primary : colors.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(target),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected ? colors.primary : colors.outline,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.primary
                                : colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            target.icon ??
                                (target.depth == 0
                                    ? Icons.widgets_outlined
                                    : Icons.folder_outlined),
                            size: 18,
                            color: isSelected
                                ? colors.onPrimary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                target.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subtitleBuilder != null) ...[
                                const SizedBox(height: 2),
                                subtitleBuilder!(context, target),
                              ] else
                                Text(
                                  'ID : ${target.id}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing,
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
