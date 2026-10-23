import 'package:material_ui/material_ui.dart';

class EditorZoneBadge extends StatelessWidget {
  const EditorZoneBadge({
    required this.label,
    required this.selected,
    this.labelKey,
    this.onTap,
    this.onHover,
    this.leading,
    this.onAdd,
    this.addKey,
    this.addTooltip,
    this.actions = const [],
    this.mouseCursor = SystemMouseCursors.click,
    super.key,
  });

  final String label;
  final Key? labelKey;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final Widget? leading;
  final VoidCallback? onAdd;
  final Key? addKey;
  final String? addTooltip;
  final List<Widget> actions;
  final MouseCursor mouseCursor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primary.withValues(alpha: .35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colors.onSurface : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        mouseCursor: mouseCursor,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onHover: onHover,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?leading,
              Text(
                label,
                key: labelKey,
                style: TextStyle(fontSize: 10, color: colors.onSurface),
              ),
              if (onAdd case final onAdd?)
                IconButton(
                  key: addKey,
                  tooltip: addTooltip,
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 24,
                  ),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  color: colors.onSurface,
                  icon: const Icon(Icons.add),
                  onPressed: onAdd,
                ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

class EditorZoneHighlight extends StatelessWidget {
  const EditorZoneHighlight({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .12),
            border: Border.all(color: colors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}
