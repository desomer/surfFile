import 'package:material_ui/material_ui.dart';

import '../models/explorer_entry.dart';
import '../theme/appearance.dart';
import '../theme/appearance_slot.dart';
import 'explorer_file_icon.dart';
import 'neon_surface.dart';
import 'press_feedback.dart';
import 'sliding_selection_list.dart';
import 'super_container.dart';
import 'scroll_edge_fade.dart';

class ExplorerEntriesView extends StatelessWidget {
  const ExplorerEntriesView({
    required this.entries,
    required this.gridView,
    required this.selectedPath,
    required this.onSelected,
    required this.onOpen,
    this.onContextMenu,
    this.onOpenWithBounds,
    super.key,
  });

  final List<ExplorerEntry> entries;
  final bool gridView;
  final String? selectedPath;
  final ValueChanged<String> onSelected;
  final ValueChanged<ExplorerEntry> onOpen;
  final void Function(ExplorerEntry, Offset)? onContextMenu;
  final void Function(ExplorerEntry, Rect, Rect)? onOpenWithBounds;

  @override
  Widget build(BuildContext context) {
    return ScrollEdgeFade(
      key: ValueKey(gridView),
      child: gridView ? _buildGrid(context) : _buildList(),
    );
  }

  Widget _buildList() {
    return SlidingSelectionList(
      paths: entries.map((entry) => entry.entity.path).toList(),
      selectedPath: selectedPath,
      itemBuilder: (context, index) => _EntryRow(
        key: ValueKey(entries[index].entity.path),
        entry: entries[index],
        selected: selectedPath == entries[index].entity.path,
        onSelected: onSelected,
        onOpen: onOpen,
        onContextMenu: onContextMenu,
        onOpenWithBounds: onOpenWithBounds,
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(30, 8, 30, 28),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: appearance.cardWidth,
        mainAxisExtent: appearance.cardHeight,
        crossAxisSpacing: appearance.spacing,
        mainAxisSpacing: appearance.spacing,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = selectedPath == entry.entity.path;
        final color = appearance.cardBackground(context, selected: selected);
        final foreground = Appearance.foreground(color);
        final style = appearance.effectiveSelectedCardStyle;
        final radius = selected ? style.radius : appearance.cardStyle.radius;
        final borderWidth = selected
            ? style.borderWidth
            : appearance.cardStyle.borderWidth;
        final gradient = selected
            ? style.fill.gradient()
            : appearance.cardStyle.fill.gradient();
        return _EntryBounds(
          key: ValueKey(entry.entity.path),
          builder: (cardKey, iconKey) => SuperContainer(
            slot: selected ? AppearanceSlot.selectedCard : AppearanceSlot.card,
            decorate: false,
            child: NeonSurface(
              key: cardKey,
              style: selected ? style.neon! : appearance.cardNeon,
              accent: appearance.accent,
              radius: radius,
              child: Material(
                color: gradient != null ? Colors.transparent : color,
                elevation: appearance.cardElevation(selected: selected),
                shadowColor: Colors.black.withValues(
                  alpha: selected
                      ? style.shadowOpacity
                      : appearance.cardStyle.shadowOpacity,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                  side: BorderSide(
                    color: selected
                        ? style.borderColor ??
                              Theme.of(context).colorScheme.primary
                        : appearance.cardStyle.borderColor ??
                              Theme.of(context).colorScheme.outlineVariant,
                    width: borderWidth,
                    style: borderWidth == 0
                        ? BorderStyle.none
                        : BorderStyle.solid,
                  ),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: PressFeedback(
                    key: ValueKey(entry.entity.path),
                    onMouseDown: () => onSelected(entry.entity.path),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(radius),
                      onTap: () {
                        if (!selected) onSelected(entry.entity.path);
                      },
                      onDoubleTap: () => _openWithBounds(
                        entry,
                        cardKey,
                        iconKey,
                        onOpen,
                        onOpenWithBounds,
                      ),
                      onSecondaryTapDown:
                          onContextMenu == null || _styleEditing(context)
                          ? null
                          : (details) =>
                                onContextMenu!(entry, details.globalPosition),
                      child: Padding(
                        padding: EdgeInsets.all(
                          selected
                              ? style.padding
                              : appearance.cardStyle.padding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: ExplorerFileIcon(
                                    key: iconKey,
                                    entry: entry,
                                    size: appearance.iconSize,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: appearance.fontSize,
                                color: foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              entry.isDirectory
                                  ? 'Dossier'
                                  : formatExplorerSize(entry.size),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: appearance.fontSize - 2,
                                color: foreground.withValues(alpha: .75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntryRow extends StatefulWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onSelected,
    required this.onOpen,
    this.onContextMenu,
    this.onOpenWithBounds,
    super.key,
  });

  final ExplorerEntry entry;
  final bool selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<ExplorerEntry> onOpen;
  final void Function(ExplorerEntry, Offset)? onContextMenu;
  final void Function(ExplorerEntry, Rect, Rect)? onOpenWithBounds;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  final cardKey = GlobalKey();
  final iconKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceScope.of(context);
    final entry = widget.entry;
    final selected = widget.selected;
    final onSelected = widget.onSelected;
    final onOpen = widget.onOpen;
    final onContextMenu = widget.onContextMenu;
    final onOpenWithBounds = widget.onOpenWithBounds;
    final color =
        appearance.cardStyle.color != null ||
            appearance.cardStyle.fill.gradient() != null ||
            selected
        ? appearance.cardBackground(context, selected: selected)
        : Theme.of(context).colorScheme.surface;
    final foreground = Appearance.foreground(color);
    final radius = selected
        ? appearance.effectiveSelectedCardStyle.radius
        : appearance.cardStyle.radius;
    return Padding(
      key: cardKey,
      padding: EdgeInsets.only(bottom: appearance.spacing / 6),
      child: SuperContainer(
        slot: selected ? AppearanceSlot.selectedCard : AppearanceSlot.card,
        decorate: false,
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(radius),
          child: PressFeedback(
            key: ValueKey(entry.entity.path),
            onMouseDown: () => onSelected(entry.entity.path),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: () {
                if (!selected) onSelected(entry.entity.path);
              },
              onDoubleTap: () => _openWithBounds(
                entry,
                cardKey,
                iconKey,
                onOpen,
                onOpenWithBounds,
              ),
              onSecondaryTapDown:
                  onContextMenu == null || _styleEditing(context)
                  ? null
                  : (details) => onContextMenu(entry, details.globalPosition),
              child: SizedBox(
                height: appearance.rowHeight,
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          ExplorerFileIcon(
                            key: iconKey,
                            entry: entry,
                            size: (appearance.iconSize * 22 / 49).clamp(16, 30),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: appearance.fontSize,
                                color: foreground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatExplorerDate(entry.modified),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: appearance.fontSize - 1,
                          color: foreground.withValues(alpha: .75),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        entry.isDirectory
                            ? 'Dossier'
                            : explorerFileType(entry.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: appearance.fontSize - 1,
                          color: foreground.withValues(alpha: .75),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        entry.isDirectory
                            ? '—'
                            : formatExplorerSize(entry.size),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: appearance.fontSize - 1,
                          color: foreground.withValues(alpha: .75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryBounds extends StatefulWidget {
  const _EntryBounds({required this.builder, super.key});

  final Widget Function(GlobalKey cardKey, GlobalKey iconKey) builder;

  @override
  State<_EntryBounds> createState() => _EntryBoundsState();
}

class _EntryBoundsState extends State<_EntryBounds> {
  final _cardKey = GlobalKey();
  final _iconKey = GlobalKey();

  @override
  Widget build(BuildContext context) => widget.builder(_cardKey, _iconKey);
}

bool _styleEditing(BuildContext context) =>
    StyleEditScope.controllerOf(context)?.value ?? false;

void _openWithBounds(
  ExplorerEntry entry,
  GlobalKey cardKey,
  GlobalKey iconKey,
  ValueChanged<ExplorerEntry> onOpen,
  void Function(ExplorerEntry, Rect, Rect)? onOpenWithBounds,
) {
  if (onOpenWithBounds == null || !entry.isDirectory) {
    onOpen(entry);
    return;
  }
  Rect bounds(GlobalKey key) {
    final box = key.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  onOpenWithBounds(entry, bounds(cardKey), bounds(iconKey));
}

String explorerFileType(String name) {
  final index = name.lastIndexOf('.');
  return index < 0 ? 'Fichier' : name.substring(index + 1).toUpperCase();
}

String formatExplorerDate(DateTime date) {
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String formatExplorerSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
}
