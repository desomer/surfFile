import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/widgets/interaction_effect_box.dart';
import 'package:super_container_layout/widgets/neon_surface.dart';
import 'package:super_container_layout/widgets/super_container.dart';

import '../models/explorer_entry.dart';
import 'drag_select_region.dart';
import 'entries_layout.dart';
import 'explorer_file_icon.dart';
import 'folder_size_cell.dart';
import 'folder_size_indicator.dart';
import '../services/folder_size_service.dart';
import 'hover_preview.dart';
import 'press_feedback.dart';
import 'sliding_selection_list.dart';
import 'scroll_edge_fade.dart';
import 'external_file_drop.dart';

class ExplorerEntriesView extends StatelessWidget {
  const ExplorerEntriesView({
    required this.entries,
    required this.gridView,
    required this.selectedPath,
    required this.onSelected,
    required this.onOpen,
    this.onContextMenu,
    this.onOpenWithBounds,
    this.selectedPaths,
    this.onSelectionChanged,
    this.onTapped,
    this.revealToken,
    this.onViewportChanged,
    this.compact = false,
    this.scrollController,
    this.onToggle,
    super.key,
  });

  /// Bascule la sélection d'un élément ; affiche une case à cocher par élément
  /// lorsqu'il est fourni.
  final ValueChanged<String>? onToggle;

  /// Liste réduite à l'icône et au nom (colonne de la vue en colonnes) ;
  /// [gridView] est alors ignoré.
  final bool compact;

  /// Défilement de la liste lorsque [onSelectionChanged] est absent.
  final ScrollController? scrollController;

  final List<ExplorerEntry> entries;
  final bool gridView;
  final String? selectedPath;
  final ValueChanged<String> onSelected;
  final ValueChanged<ExplorerEntry> onOpen;
  final void Function(ExplorerEntry, Offset)? onContextMenu;
  final void Function(ExplorerEntry, Rect, Rect)? onOpenWithBounds;

  /// Sélection multiple ; par défaut, seulement [selectedPath].
  final Set<String>? selectedPaths;

  /// Active la sélection par cadre lorsqu'il est fourni.
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// Clic relâché sans glisser ; à défaut, [onSelected] si non sélectionné.
  final ValueChanged<String>? onTapped;

  /// Change pour faire défiler jusqu'à [selectedPath] (navigation clavier).
  final Object? revealToken;

  final ValueChanged<Size>? onViewportChanged;

  Set<String> get _selection => selectedPaths ?? {?selectedPath};

  void _tap(String path, bool selected) {
    final onTapped = this.onTapped;
    if (onTapped != null) {
      onTapped(path);
    } else if (!selected) {
      onSelected(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSelectionChanged = this.onSelectionChanged;
    final grid = gridView && !compact;
    Widget view(ScrollController? controller) => ScrollEdgeFade(
      child: grid ? _buildGrid(context, controller) : _buildList(controller),
    );
    if (onSelectionChanged == null) {
      return KeyedSubtree(key: ValueKey(grid), child: view(scrollController));
    }
    final appearance = AppearanceScope.of(context);
    EntriesLayout layout(Size viewport) => EntriesLayout(
      grid: grid,
      compact: compact,
      appearance: appearance,
      viewport: viewport,
      count: entries.length,
    );
    return DragSelectRegion(
      key: ValueKey(grid),
      builder: (context, controller) => view(controller),
      hitTest: (rect, viewport) => layout(viewport).hits(rect),
      selectedIndexes: () {
        final selection = _selection;
        return {
          for (var i = 0; i < entries.length; i++)
            if (selection.contains(entries[i].entity.path)) i,
        };
      },
      onChanged: (indexes) => onSelectionChanged({
        for (final index in indexes) entries[index].entity.path,
      }),
      revealToken: revealToken,
      reveal: (viewport) {
        final index = entries.indexWhere(
          (entry) => entry.entity.path == selectedPath,
        );
        return index < 0 ? null : layout(viewport).itemRect(index);
      },
      onViewport: onViewportChanged,
    );
  }

  Widget _buildList(ScrollController? controller) {
    final selection = _selection;
    return SlidingSelectionList(
      controller: controller,
      horizontalPadding: compact
          ? EntriesLayout.compactHorizontalPadding
          : EntriesLayout.listPadding.left,
      paths: entries.map((entry) => entry.entity.path).toList(),
      selectedPath: selectedPath,
      selectedPaths: selection,
      itemBuilder: (context, index) => ExternalDropDestination(
        path: entries[index].isDirectory ? entries[index].entity.path : null,
        child: _EntryRow(
          key: ValueKey(entries[index].entity.path),
          compact: compact,
          entry: entries[index],
          selected: selection.contains(entries[index].entity.path),
          onSelected: onSelected,
          onToggle: onToggle,
          onTapped: (path) => _tap(path, _selection.contains(path)),
          onOpen: onOpen,
          onContextMenu: onContextMenu,
          onOpenWithBounds: onOpenWithBounds,
          siblingFolders: _folderPaths,
          siblingSizes: _sizes,
        ),
      ),
    );
  }

  /// Tailles de tous les éléments (dossiers : taille calculée, sinon 0).
  List<int> _sizes() => [
    for (final entry in entries)
      entry.isDirectory
          ? FolderSizeService.bytesOf(entry.entity.path) ?? 0
          : entry.size,
  ];

  List<String> _folderPaths() => [
    for (final entry in entries)
      if (entry.isDirectory) entry.entity.path,
  ];

  Widget _buildGrid(BuildContext context, ScrollController? controller) {
    final appearance = AppearanceScope.of(context);
    final selection = _selection;
    return GridView.builder(
      controller: controller,
      padding: EntriesLayout.gridPadding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: appearance.cardWidth,
        mainAxisExtent: appearance.cardHeight,
        crossAxisSpacing: appearance.spacing,
        mainAxisSpacing: appearance.spacing,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = selection.contains(entry.entity.path);
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
        return ExternalDropDestination(
          path: entry.isDirectory ? entry.entity.path : null,
          child: _EntryBounds(
            key: ValueKey(entry.entity.path),
            builder: (cardKey, iconKey) => SuperContainer(
              slot: selected
                  ? AppearanceSlot.selectedCard
                  : AppearanceSlot.card,
              decorate: false,
              child: InteractionEffectBox(
                effect:
                    (selected ? style : appearance.cardStyle).interactionEffect,
                ownsHover: true,
                hover: (selected ? style : appearance.cardStyle).hoverEffect,
                hoverColor: (selected ? style : appearance.cardStyle).hoverBase(
                  appearance.accent,
                ),
                radius: radius,
                builder: (context, boost) => NeonSurface(
                  key: cardKey,
                  style: selected ? style.neon! : appearance.cardNeon,
                  accent: appearance.accent,
                  radius: radius,
                  child: Material(
                    color: gradient != null ? Colors.transparent : color,
                    elevation:
                        (appearance.cardElevation(selected: selected) + boost)
                            .clamp(0.0, double.infinity),
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
                        onMouseDown: () =>
                            _mouseDown(onSelected, entry.entity.path),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(radius),
                          onTap: () {
                            _tap(entry.entity.path, selected);
                            if (_isDoubleClick(entry.entity.path)) {
                              _openWithBounds(
                                entry,
                                cardKey,
                                iconKey,
                                onOpen,
                                onOpenWithBounds,
                              );
                            }
                          },
                          onSecondaryTapDown:
                              onContextMenu == null || _styleEditing(context)
                              ? null
                              : (details) => onContextMenu!(
                                  entry,
                                  details.globalPosition,
                                ),
                          child: Stack(
                            children: [
                              Padding(
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
                                        color: foreground.withValues(
                                          alpha: .75,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (onToggle != null)
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: _SelectBox(
                                    checked: selected,
                                    onChanged: () =>
                                        onToggle!(entry.entity.path),
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
    required this.onTapped,
    required this.onOpen,
    this.onContextMenu,
    this.onOpenWithBounds,
    this.compact = false,
    this.onToggle,
    this.siblingFolders,
    this.siblingSizes,
    super.key,
  });

  final List<String> Function()? siblingFolders;
  final List<int> Function()? siblingSizes;
  final ValueChanged<String>? onToggle;
  final bool compact;
  final ExplorerEntry entry;
  final bool selected;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onTapped;
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
    final rowStyle = selected
        ? appearance.effectiveSelectedCardStyle
        : appearance.cardStyle;
    return Padding(
      key: cardKey,
      padding: EdgeInsets.only(bottom: appearance.spacing / 6),
      child: SuperContainer(
        slot: selected ? AppearanceSlot.selectedCard : AppearanceSlot.card,
        decorate: false,
        child: InteractionEffectBox(
          effect: rowStyle.interactionEffect,
          ownsHover: true,
          hover: rowStyle.hoverEffect,
          hoverColor: rowStyle.hoverBase(appearance.accent),
          radius: radius,
          builder: (context, _) => Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(radius),
            child: PressFeedback(
              key: ValueKey(entry.entity.path),
              onMouseDown: () => _mouseDown(onSelected, entry.entity.path),
              child: InkWell(
                borderRadius: BorderRadius.circular(radius),
                onTap: () {
                  widget.onTapped(entry.entity.path);
                  // En colonnes, un dossier s'ouvre dès le premier clic.
                  if (_isDoubleClick(entry.entity.path) &&
                      !(widget.compact && entry.isDirectory)) {
                    _openWithBounds(
                      entry,
                      cardKey,
                      iconKey,
                      onOpen,
                      onOpenWithBounds,
                    );
                  }
                },
                onSecondaryTapDown:
                    onContextMenu == null || _styleEditing(context)
                    ? null
                    : (details) => onContextMenu(entry, details.globalPosition),
                child: HoverPreview(
                  entry: entry,
                  child: SizedBox(
                    height: appearance.rowHeight,
                    child: Stack(
                      children: [
                        if (!widget.compact)
                          Positioned.fill(
                            child: SizeRowBackground(
                              bytes: () => entry.isDirectory
                                  ? FolderSizeService.bytesOf(entry.entity.path)
                                  : entry.size,
                              siblingSizes: widget.siblingSizes,
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Row(
                                children: [
                                  if (widget.onToggle case final onToggle?)
                                    _SelectBox(
                                      checked: selected,
                                      onChanged: () =>
                                          onToggle(entry.entity.path),
                                    )
                                  else
                                    SizedBox(width: widget.compact ? 8 : 12),
                                  ExplorerFileIcon(
                                    key: iconKey,
                                    entry: entry,
                                    size: (appearance.iconSize * 22 / 49).clamp(
                                      16,
                                      30,
                                    ),
                                  ),
                                  SizedBox(width: widget.compact ? 10 : 12),
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
                                  if (widget.compact && entry.isDirectory)
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18,
                                      color: foreground.withValues(alpha: .6),
                                    ),
                                  if (widget.compact) const SizedBox(width: 6),
                                ],
                              ),
                            ),
                            if (!widget.compact) ...[
                              Expanded(
                                flex: 2,
                                child: Text(
                                  formatExplorerDateTime(entry.modified),
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
                                child: entry.isDirectory
                                    ? FolderSizeCell(
                                        path: entry.entity.path,
                                        siblingFolders: widget.siblingFolders,
                                        siblingSizes: widget.siblingSizes,
                                        style: TextStyle(
                                          fontSize: appearance.fontSize - 1,
                                          color: foreground.withValues(
                                            alpha: .75,
                                          ),
                                        ),
                                      )
                                    : Align(
                                        alignment: Alignment.centerLeft,
                                        child: SizeGauge(
                                          bytes: () => entry.size,
                                          siblingSizes: widget.siblingSizes,
                                          child: Text(
                                            formatExplorerSize(entry.size),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: appearance.fontSize - 1,
                                              color: foreground.withValues(
                                                alpha: .75,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ],
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

/// Date et heure locales, ex. `05/03/2026 09:07`.
String formatExplorerDateTime(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${formatExplorerDate(local)} $hour:$minute';
}

String formatExplorerSize(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
}

String? _lastClickPath;
DateTime _lastClickAt = DateTime(0);

/// Détecte le double-clic sans InkWell.onDoubleTap, qui retarde onTap du
/// délai du double-clic : la sélection reste ainsi immédiate.
bool _isDoubleClick(String path) {
  final now = DateTime.now();
  final repeated =
      _lastClickPath == path &&
      now.difference(_lastClickAt) <= kDoubleTapTimeout;
  _lastClickPath = repeated ? null : path;
  _lastClickAt = now;
  return repeated;
}

/// Appui en cours sur une case à cocher : la case gère seule la sélection, le
/// `onMouseDown` de la ligne ou de la carte ne doit pas la remplacer.
bool _checkboxDown = false;

void _mouseDown(ValueChanged<String> onSelected, String path) {
  if (!_checkboxDown) onSelected(path);
}

class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.checked, required this.onChanged});

  final bool checked;
  final VoidCallback onChanged;

  static const size = 24.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _checkboxDown = true,
      onPointerUp: (_) => _checkboxDown = false,
      onPointerCancel: (_) => _checkboxDown = false,
      child: SizedBox(
        width: size,
        height: size,
        child: Checkbox(
          value: checked,
          onChanged: (_) => onChanged(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
