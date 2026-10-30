import 'package:material_ui/material_ui.dart';

import '../overlay/editor_zoom.dart';
import '../slots/editor_slot.dart';

/// Élément de base affiché dans le sélecteur de cible d'un assistant d'édition
/// (Comportements, Données & Liaisons JSON, etc.).
abstract interface class EditorTargetItem {
  String get id;
  String get label;
  EditorSlotState? get slot;
  IconData? get icon;
  int get depth;
}

/// Liste réutilisable permettant de sélectionner un élément cible dans la
/// hiérarchie (composant courant ou conteneurs parents) avec mise en avant
/// (cadre d'overlay) du composant survolé.
class EditorTargetSelector<T extends EditorTargetItem> extends StatefulWidget {
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
  State<EditorTargetSelector<T>> createState() =>
      _EditorTargetSelectorState<T>();
}

class _EditorTargetSelectorState<T extends EditorTargetItem>
    extends State<EditorTargetSelector<T>> {
  EditorSlotState? _hoveredSlot;

  void _onHoverTarget(EditorSlotState? slot, bool entered) {
    if (entered) {
      _hoveredSlot = slot;
      EditorSlotState.setHighlightedTarget(slot);
    } else if (identical(_hoveredSlot, slot)) {
      _hoveredSlot = null;
      EditorSlotState.clearHighlightedTarget(slot);
    }
  }

  @override
  void dispose() {
    if (_hoveredSlot != null) {
      EditorSlotState.clearHighlightedTarget(_hoveredSlot);
      _hoveredSlot = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final target in widget.targets)
          Builder(
            builder: (context) {
              final isSelected = widget.isSelectedPredicate != null
                  ? widget.isSelectedPredicate!(target, widget.selected)
                  : identical(target, widget.selected) ||
                        (target.id == widget.selected.id &&
                            target.depth == widget.selected.depth);
              final trailing = widget.trailingBuilder?.call(context, target);

              return MouseRegion(
                onEnter: (_) => _onHoverTarget(target.slot, true),
                onExit: (_) => _onHoverTarget(target.slot, false),
                child: Card(
                  key:
                      widget.itemKeyBuilder?.call(target) ??
                      ValueKey('editor-target-${target.id}-${target.depth}'),
                  elevation: isSelected ? 2 : 0,
                  color: isSelected
                      ? colors.secondaryContainer.withValues(alpha: .4)
                      : colors.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? colors.primary
                          : colors.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final slotCtx = target.slot?.context;
                      if (slotCtx != null && slotCtx.mounted) {
                        EditorZoomScope.controllerOf(context)?.dialog
                            .retarget(slotCtx);
                      }
                      widget.onSelected(target);
                    },
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
                                if (widget.subtitleBuilder != null) ...[
                                  const SizedBox(height: 2),
                                  widget.subtitleBuilder!(context, target),
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
                ),
              );
            },
          ),
      ],
    );
  }
}
