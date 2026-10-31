import 'package:flutter/gestures.dart' show kDoubleTapTimeout, kDoubleTapSlop;
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';

import '../../../theme/surffile_appearance_slots.dart';

import 'package:super_container_layout/widgets/surfaces/interaction_effect_box.dart';
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/widgets/surfaces/neon_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';

import '../../../models/explorer_entry.dart';
import '../../interaction/drag_select_region.dart';
import 'entries_layout.dart';
import 'explorer_file_icon.dart';
import '../../folder_size/folder_size_cell.dart';
import '../../folder_size/folder_size_indicator.dart';
import '../../../services/folder_size_service.dart';
import '../../preview/hover_preview.dart';
import '../../interaction/press_feedback.dart';
import '../../interaction/sliding_selection_list.dart';
import '../../interaction/scroll_edge_fade.dart';
import '../../file_operations/external_file_drop.dart';

class ExplorerEntriesView extends StatefulWidget {
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

  @override
  State<ExplorerEntriesView> createState() => _ExplorerEntriesViewState();
}

class _ExplorerEntriesViewState extends State<ExplorerEntriesView> {
  late List<String> _paths;
  late Map<String, int> _indexByPath;
  List<String>? _folderPathsCache;
  List<String>? _selectedDragPathsCache;
  int? _maxSizeRevision;
  List<int> _maxSizeList = const [0];
  late List<Widget?> _rowWidgets;
  late List<Object?> _rowKeys;
  ThemeData? _cachedParentTheme;
  ThemeData? _cachedNoHoverTheme;

  Set<String> get _selection => widget.selectedPaths ?? {?widget.selectedPath};

  @override
  void initState() {
    super.initState();
    _rebuildEntriesCache();
  }

  @override
  void didUpdateWidget(ExplorerEntriesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) {
      _rebuildEntriesCache();
    } else if (oldWidget.selectedPath != widget.selectedPath ||
        !identical(oldWidget.selectedPaths, widget.selectedPaths)) {
      _selectedDragPathsCache = null;
    }
  }

  void _rebuildEntriesCache() {
    final entries = widget.entries;
    _paths = [for (final entry in entries) entry.entity.path];
    _indexByPath = {for (var i = 0; i < _paths.length; i++) _paths[i]: i};
    _folderPathsCache = null;
    _selectedDragPathsCache = null;
    _maxSizeRevision = null;
    _rowWidgets = List<Widget?>.filled(_paths.length, null);
    _rowKeys = List<Object?>.filled(_paths.length, null);
  }

  void _tap(String path, bool selected) {
    final onTapped = widget.onTapped;
    if (onTapped != null) {
      onTapped(path);
    } else if (!selected) {
      widget.onSelected(path);
    }
  }

  void _onRowSelected(String path) => widget.onSelected(path);
  void _onRowToggle(String path) => widget.onToggle?.call(path);
  void _onRowTapped(String path) => _tap(path, _selection.contains(path));
  void _onRowOpen(ExplorerEntry entry) => widget.onOpen(entry);
  void _onRowContextMenu(ExplorerEntry entry, Offset pos) =>
      widget.onContextMenu?.call(entry, pos);
  void _onRowOpenWithBounds(ExplorerEntry entry, Rect card, Rect icon) =>
      widget.onOpenWithBounds?.call(entry, card, icon);

  @override
  Widget build(BuildContext context) {
    final onSelectionChanged = widget.onSelectionChanged;
    final grid = widget.gridView && !widget.compact;
    final parentTheme = Theme.of(context);
    if (!identical(parentTheme, _cachedParentTheme)) {
      _cachedParentTheme = parentTheme;
      _cachedNoHoverTheme =
          parentTheme.hoverColor == Colors.transparent
          ? parentTheme
          : parentTheme.copyWith(hoverColor: Colors.transparent);
    }
    Widget view(ScrollController? controller) => Theme(
      data: _cachedNoHoverTheme!,
      child: ScrollEdgeFade(
        child: grid ? _buildGrid(context, controller) : _buildList(context, controller),
      ),
    );
    if (onSelectionChanged == null) {
      return KeyedSubtree(
        key: ValueKey(grid),
        child: view(widget.scrollController),
      );
    }
    final appearance = AppearanceScope.of(context);
    final entries = widget.entries;
    EntriesLayout layout(Size viewport) => EntriesLayout(
      grid: grid,
      compact: widget.compact,
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
          for (final path in selection)
            if (_indexByPath[path] case final index?) index,
        };
      },
      onChanged: (indexes) => onSelectionChanged({
        for (final index in indexes) entries[index].entity.path,
      }),
      revealToken: widget.revealToken,
      reveal: (viewport) {
        final selected = widget.selectedPath;
        final index = selected == null ? -1 : (_indexByPath[selected] ?? -1);
        return index < 0 ? null : layout(viewport).itemRect(index);
      },
      onViewport: widget.onViewportChanged,
    );
  }

  Widget _buildList(BuildContext context, ScrollController? controller) {
    final selection = _selection;
    final dragMode = SurfFilePreferencesScope.of(context).fileDragMode;
    final compact = widget.compact;
    final entries = widget.entries;
    return SlidingSelectionList(
      controller: controller,
      horizontalPadding: compact
          ? EntriesLayout.compactHorizontalPadding
          : EntriesLayout.listPadding.left,
      paths: _paths,
      selectedPath: widget.selectedPath,
      selectedPaths: selection,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final path = _paths[index];
        final isSelected = selection.contains(path);
        final dragPaths = isSelected ? _selectedDragPaths : null;
        final rowKey = (
          entry,
          isSelected,
          dragPaths,
          dragMode,
          compact,
          widget.onToggle != null,
          widget.onContextMenu != null,
          widget.onOpenWithBounds != null,
        );
        if (_rowKeys[index] == rowKey && _rowWidgets[index] != null) {
          return _rowWidgets[index]!;
        }
        final paths = dragPaths ?? [path];
        final built = ExternalDropDestination(
          path: entry.isDirectory ? path : null,
          child: ExternalFileDragSource(
            paths: paths,
            label: entry.name,
            mode: dragMode,
            selected: isSelected,
            child: _EntryRow(
              key: ValueKey(path),
              compact: compact,
              entry: entry,
              selected: isSelected,
              onSelected: _onRowSelected,
              onToggle: widget.onToggle == null ? null : _onRowToggle,
              onTapped: _onRowTapped,
              onOpen: _onRowOpen,
              onContextMenu:
                  widget.onContextMenu == null ? null : _onRowContextMenu,
              onOpenWithBounds:
                  widget.onOpenWithBounds == null ? null : _onRowOpenWithBounds,
              siblingFolders: _folderPaths,
              siblingSizes: _sizes,
            ),
          ),
        );
        _rowKeys[index] = rowKey;
        _rowWidgets[index] = built;
        return built;
      },
    );
  }

  /// Taille maximale des éléments du dossier (dossiers : taille calculée, sinon 0).
  List<int> _sizes() {
    final rev = FolderSizeService.revision.value;
    if (_maxSizeRevision != rev) {
      _maxSizeRevision = rev;
      var maxBytes = 0;
      for (final entry in widget.entries) {
        final bytes = entry.isDirectory
            ? FolderSizeService.bytesOf(entry.entity.path) ?? 0
            : entry.size;
        if (bytes > maxBytes) maxBytes = bytes;
      }
      _maxSizeList = [maxBytes];
    }
    return _maxSizeList;
  }

  List<String> _folderPaths() => _folderPathsCache ??= [
    for (final entry in widget.entries)
      if (entry.isDirectory) entry.entity.path,
  ];

  List<String> get _selectedDragPaths => _selectedDragPathsCache ??= [
    for (final candidate in widget.entries)
      if (_selection.contains(candidate.entity.path)) candidate.entity.path,
  ];

  List<String> _pathsToDrag(ExplorerEntry entry) {
    final path = entry.entity.path;
    if (!_selection.contains(path)) return [path];
    return _selectedDragPaths;
  }

  Widget _buildGrid(BuildContext context, ScrollController? controller) {
    final appearance = AppearanceScope.of(context);
    final selection = _selection;
    final entries = widget.entries;
    final onSelected = widget.onSelected;
    final onOpen = widget.onOpen;
    final onContextMenu = widget.onContextMenu;
    final onOpenWithBounds = widget.onOpenWithBounds;
    final onToggle = widget.onToggle;
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
        final dragMode = SurfFilePreferencesScope.of(context).fileDragMode;
        final cardStyle = appearance.style('card');
        final style = SurfFileAppearanceSlots.selectedCard.read(appearance);
        final color = cardColor(
          context,
          selected ? style : cardStyle,
          selected: selected,
        );
        final foreground = foregroundForCard(color);
        final radius = selected ? style.radius : cardStyle.radius;
        final borderWidth = selected
            ? style.borderWidth
            : cardStyle.borderWidth;
        final gradient = selected
            ? style.fill.gradient()
            : cardStyle.fill.gradient();
        final image = selected
            ? style.fill.decorationImage()
            : cardStyle.fill.decorationImage();
        return ExternalDropDestination(
          path: entry.isDirectory ? entry.entity.path : null,
          child: ExternalFileDragSource(
            paths: _pathsToDrag(entry),
            label: entry.name,
            mode: dragMode,
            selected: selected,
            child: _EntryBounds(
              key: ValueKey(entry.entity.path),
              builder: (cardKey, iconKey) => EditableSurface(
                slot: selected
                    ? SurfFileAppearanceSlots.selectedCard
                    : SurfFileAppearanceSlots.card,
                decorate: false,
                child: InteractionEffectBox(
                  effect: (selected ? style : cardStyle).interactionEffect,
                  ownsHover: true,
                  hover: (selected ? style : cardStyle).hoverEffect,
                  hoverColor: (selected ? style : cardStyle).hoverBase(
                    appearance.accent,
                  ),
                  radius: radius,
                  builder: (context, boost) => NeonSurface(
                    key: cardKey,
                    style: selected
                        ? style.neon!
                        : cardStyle.neon ?? const NeonStyle(),
                    accent: appearance.accent,
                    radius: radius,
                    child: Material(
                      color: gradient != null ? Colors.transparent : color,
                      elevation:
                          ((selected ? style : cardStyle).elevation + boost)
                              .clamp(0.0, double.infinity),
                      shadowColor: Colors.black.withValues(
                        alpha: selected
                            ? style.shadowOpacity
                            : cardStyle.shadowOpacity,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(radius),
                        side: BorderSide(
                          color: selected
                              ? style.borderColor ??
                                    Theme.of(context).colorScheme.primary
                              : cardStyle.borderColor ??
                                    Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                          width: borderWidth,
                          style: borderWidth == 0
                              ? BorderStyle.none
                              : BorderStyle.solid,
                        ),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: gradient,
                          image: image,
                          borderRadius: BorderRadius.circular(radius),
                        ),
                        child: PressFeedback(
                          key: ValueKey(entry.entity.path),
                          onMouseDown: () =>
                              _mouseDown(onSelected, entry.entity.path),
                          onPress: (event) =>
                              _recordPress(entry.entity.path, event),
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
                                : (details) => onContextMenu(
                                    entry,
                                    details.globalPosition,
                                  ),
                            child: Stack(
                              children: [
                                Padding(
                                  padding: EdgeInsets.all(
                                    selected
                                        ? style.padding
                                        : cardStyle.padding,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Center(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: ExternalFileDragHandle(
                                              child: ExplorerFileIcon(
                                                key: iconKey,
                                                entry: entry,
                                                size: appearance.iconSize,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ExternalFileDragHandle(
                                        child: Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: appearance.fontSize,
                                            color: foreground,
                                            fontWeight: FontWeight.w600,
                                          ),
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
                                          onToggle(entry.entity.path),
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
    final cardStyle = appearance.style('card');
    final rowStyle = selected
        ? SurfFileAppearanceSlots.selectedCard.read(appearance)
        : cardStyle;
    final color =
        cardStyle.color != null || cardStyle.fill.gradient() != null || selected
        ? cardColor(context, rowStyle, selected: selected)
        : Theme.of(context).colorScheme.surface;
    final foreground = foregroundForCard(color);
    final radius = rowStyle.radius;
    return Padding(
      key: cardKey,
      padding: EdgeInsets.only(bottom: appearance.spacing / 6),
      child: EditableSurface(
        slot: selected
            ? SurfFileAppearanceSlots.selectedCard
            : SurfFileAppearanceSlots.card,
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
              onPress: (event) => _recordPress(entry.entity.path, event),
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
                                  ExternalFileDragHandle(
                                    child: ExplorerFileIcon(
                                      key: iconKey,
                                      entry: entry,
                                      size: (appearance.iconSize * 22 / 49)
                                          .clamp(16, 30),
                                    ),
                                  ),
                                  SizedBox(width: widget.compact ? 10 : 12),
                                  Expanded(
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: ExternalFileDragHandle(
                                        child: Text(
                                          entry.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: appearance.fontSize,
                                            color: foreground,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
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

/// Délai du double-clic de Windows par défaut ; [kDoubleTapTimeout] (300 ms)
/// est plus court que la plupart des réglages système.
const _doubleClickTime = Duration(milliseconds: 500);

String? _lastPressPath;
Duration _lastPressAt = Duration.zero;
Offset _lastPressPosition = Offset.zero;
String? _doubleClickPath;

/// Note l'appui sur [path] : le second appui rapproché arme le double-clic.
///
/// L'intervalle est mesuré sur l'horodatage des événements, pas à leur
/// traitement : le premier clic sur un élément non sélectionné reconstruit la
/// page, ce qui retarde le traitement du second clic.
void _recordPress(String path, PointerDownEvent event) {
  final repeated =
      _lastPressPath == path &&
      event.timeStamp - _lastPressAt <= _doubleClickTime &&
      (event.position - _lastPressPosition).distance <= kDoubleTapSlop;
  _doubleClickPath = repeated ? path : null;
  _lastPressPath = repeated ? null : path;
  _lastPressAt = event.timeStamp;
  _lastPressPosition = event.position;
}

/// Détecte le double-clic sans InkWell.onDoubleTap, qui retarde onTap du
/// délai du double-clic : la sélection reste ainsi immédiate.
bool _isDoubleClick(String path) {
  final repeated = _doubleClickPath == path;
  _doubleClickPath = null;
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
