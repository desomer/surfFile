import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show kDoubleTapTimeout, kPrimaryMouseButton;
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/appearance.dart';

import '../models/explorer_entry.dart';
import '../models/treemap_layout.dart';
import '../services/folder_size_service.dart';
import 'explorer_entries_view.dart' show formatExplorerSize;
import 'folder_size_indicator.dart';
import 'external_file_drop.dart';

/// Vue « carte thermique » : chaque élément est un rectangle dont la surface
/// est proportionnelle à sa taille, et la couleur (vert → rouge) d'autant plus
/// chaude qu'il est gros. Les tailles des sous-dossiers sont calculées à
/// l'ouverture de la vue.
class ExplorerHeatmapView extends StatefulWidget {
  const ExplorerHeatmapView({
    required this.entries,
    required this.selectedPaths,
    required this.onOpen,
    this.onPointerSelect,
    this.onTapped,
    this.onContextMenu,
    super.key,
  });

  final List<ExplorerEntry> entries;
  final Set<String> selectedPaths;
  final ValueChanged<ExplorerEntry> onOpen;

  /// Appui de la souris sur une case (avant le relâchement).
  final ValueChanged<String>? onPointerSelect;
  final ValueChanged<String>? onTapped;
  final void Function(ExplorerEntry, Offset)? onContextMenu;

  /// Cases moins larges ou moins hautes que ceci (en pixels) : non dessinées.
  static const minTileSide = 4.0;

  /// Nombre maximal de cases dessinées (les plus grosses).
  static const maxTiles = 800;

  @override
  State<ExplorerHeatmapView> createState() => _ExplorerHeatmapViewState();
}

class _ExplorerHeatmapViewState extends State<ExplorerHeatmapView> {
  static const _concurrency = 4;

  final _queue = <String>[];
  final _requested = <String>{};
  int _workers = 0;

  @override
  void initState() {
    super.initState();
    _autoCompute();
  }

  @override
  void didUpdateWidget(ExplorerHeatmapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries)) _autoCompute();
  }

  @override
  void dispose() {
    _queue.clear();
    super.dispose();
  }

  List<String> get _folders => [
    for (final entry in widget.entries)
      if (entry.isDirectory) entry.entity.path,
  ];

  /// Calcule une fois les dossiers inconnus ; une annulation n'est pas relancée
  /// d'office.
  void _autoCompute() {
    final fresh = [
      for (final path in FolderSizeService.uncomputed(_folders))
        if (_requested.add(path)) path,
    ];
    if (fresh.isEmpty) return;
    // Les notifiers des tailles ne doivent pas changer pendant la construction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enqueue(fresh);
    });
  }

  void _enqueue(Iterable<String> paths) {
    _queue.addAll(paths);
    while (_workers < _concurrency && _queue.isNotEmpty) {
      _workers++;
      _work();
    }
  }

  Future<void> _work() async {
    while (_queue.isNotEmpty && mounted) {
      await FolderSizeService.compute(_queue.removeAt(0));
    }
    _workers--;
  }

  void _cancel() {
    _queue.clear();
    for (final path in _folders) {
      if (FolderSizeService.of(path).value.computing) {
        FolderSizeService.cancel(path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    return ListenableBuilder(
      listenable: Listenable.merge([
        FolderSizeService.revision,
        for (final path in folders) FolderSizeService.of(path),
      ]),
      builder: (context, _) {
        final sized = <(ExplorerEntry, int)>[];
        var computing = 0;
        var unknown = 0;
        for (final entry in widget.entries) {
          final int? bytes;
          if (entry.isDirectory) {
            final state = FolderSizeService.of(entry.entity.path).value;
            bytes = state.bytes;
            if (state.computing) {
              computing++;
            } else if (bytes == null) {
              unknown++;
            }
          } else {
            bytes = entry.size;
          }
          if (bytes != null && bytes > 0) sized.add((entry, bytes));
        }
        sized.sort((a, b) => b.$2.compareTo(a.$2));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              total: sized.fold(0, (sum, item) => sum + item.$2),
              computing: computing,
              unknown: unknown,
              onCancel: _cancel,
              onCompute: () => _enqueue(FolderSizeService.uncomputed(folders)),
            ),
            Expanded(
              child: sized.isEmpty
                  ? Center(
                      child: Text(
                        computing > 0
                            ? 'Calcul des tailles…'
                            : 'Aucun élément avec une taille à afficher',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : _HeatmapCanvas(
                      sized: sized,
                      selectedPaths: widget.selectedPaths,
                      onOpen: widget.onOpen,
                      onPointerSelect: widget.onPointerSelect,
                      onTapped: widget.onTapped,
                      onContextMenu: widget.onContextMenu,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.computing,
    required this.unknown,
    required this.onCancel,
    required this.onCompute,
  });

  final int total;
  final int computing;
  final int unknown;
  final VoidCallback onCancel;
  final VoidCallback onCompute;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Text('Total : ${formatExplorerSize(total)}', style: style),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(children: _status(style)),
              ),
            ),
            if (constraints.maxWidth >= 480) ..._legend(style),
          ],
        ),
      ),
    );
  }

  List<Widget> _status(TextStyle style) => [
    if (computing > 0) ...[
      const SizedBox.square(
        key: ValueKey('heatmap-progress'),
        dimension: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 6),
      Text(
        'Calcul de $computing dossier${computing == 1 ? '' : 's'}…',
        style: style,
      ),
      TextButton(
        key: const ValueKey('heatmap-cancel'),
        onPressed: onCancel,
        child: const Text('Annuler'),
      ),
    ] else if (unknown > 0)
      TextButton(
        key: const ValueKey('heatmap-compute'),
        onPressed: onCompute,
        child: Text('Calculer $unknown dossier${unknown == 1 ? '' : 's'}'),
      ),
  ];

  List<Widget> _legend(TextStyle style) => [
    Text('Petit', style: style),
    const SizedBox(width: 6),
    Container(
      key: const ValueKey('heatmap-legend'),
      width: 90,
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          colors: [
            for (var i = 0; i <= 4; i++) FolderSizeIndicator.color(i / 4),
          ],
        ),
      ),
    ),
    const SizedBox(width: 6),
    Text('Gros', style: style),
  ];
}

class _HeatmapCanvas extends StatefulWidget {
  const _HeatmapCanvas({
    required this.sized,
    required this.selectedPaths,
    required this.onOpen,
    this.onPointerSelect,
    this.onTapped,
    this.onContextMenu,
  });

  /// Éléments de taille connue et non nulle, du plus gros au plus petit.
  final List<(ExplorerEntry, int)> sized;
  final Set<String> selectedPaths;
  final ValueChanged<ExplorerEntry> onOpen;
  final ValueChanged<String>? onPointerSelect;
  final ValueChanged<String>? onTapped;
  final void Function(ExplorerEntry, Offset)? onContextMenu;

  @override
  State<_HeatmapCanvas> createState() => _HeatmapCanvasState();
}

class _HeatmapCanvasState extends State<_HeatmapCanvas> {
  String? _lastTapPath;
  DateTime _lastTapAt = DateTime(0);

  /// Détecte le double-clic sans retarder la sélection du premier clic.
  bool _isDoubleTap(String path) {
    final now = DateTime.now();
    final repeated =
        _lastTapPath == path && now.difference(_lastTapAt) <= kDoubleTapTimeout;
    _lastTapPath = repeated ? null : path;
    _lastTapAt = now;
    return repeated;
  }

  @override
  Widget build(BuildContext context) {
    final sized = widget.sized;
    final total = sized.fold<int>(0, (sum, item) => sum + item.$2);
    // Échelle logarithmique : un seul gros élément n'écrase pas les couleurs.
    final low = math.log(sized.last.$2);
    final span = math.log(sized.first.$2) - low;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rects = squarifyTreemap([
          for (final item in sized) item.$2.toDouble(),
        ], Offset.zero & constraints.biggest);
        final tiles = <Widget>[];
        for (var i = 0; i < sized.length; i++) {
          final rect = rects[i].deflate(1);
          if (rect.width < ExplorerHeatmapView.minTileSide ||
              rect.height < ExplorerHeatmapView.minTileSide) {
            continue;
          }
          if (tiles.length >= ExplorerHeatmapView.maxTiles) break;
          final (entry, bytes) = sized[i];
          final path = entry.entity.path;
          tiles.add(
            Positioned.fromRect(
              key: ValueKey(path),
              rect: rect,
              child: ExternalDropDestination(
                path: entry.isDirectory ? path : null,
                child: _HeatTile(
                entry: entry,
                bytes: bytes,
                share: bytes / total,
                heat: span <= 0 ? .5 : (math.log(bytes) - low) / span,
                selected: widget.selectedPaths.contains(path),
                onPointerDown: () => widget.onPointerSelect?.call(path),
                onTap: () {
                  widget.onTapped?.call(path);
                  if (_isDoubleTap(path)) widget.onOpen(entry);
                },
                onContextMenu: widget.onContextMenu == null
                    ? null
                    : (position) => widget.onContextMenu!(entry, position),
                ),
              ),
            ),
          );
        }
        return Stack(
          key: const ValueKey('heatmap-canvas'),
          clipBehavior: Clip.hardEdge,
          children: tiles,
        );
      },
    );
  }
}

class _HeatTile extends StatefulWidget {
  const _HeatTile({
    required this.entry,
    required this.bytes,
    required this.share,
    required this.heat,
    required this.selected,
    required this.onPointerDown,
    required this.onTap,
    this.onContextMenu,
  });

  final ExplorerEntry entry;
  final int bytes;

  /// Part (0..1) de la taille totale affichée.
  final double share;

  /// Chaleur (0..1) de la couleur.
  final double heat;
  final bool selected;
  final VoidCallback onPointerDown;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  State<_HeatTile> createState() => _HeatTileState();
}

class _HeatTileState extends State<_HeatTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final color = FolderSizeIndicator.color(widget.heat.clamp(0.0, 1.0));
    final accent = AppearanceScope.of(context).accent;
    final percent = widget.share * 100;
    return Tooltip(
      message:
          '${entry.name}\n${formatExplorerSize(widget.bytes)} · '
          '${percent < .1 ? '<0,1' : percent.toStringAsFixed(1).replaceAll('.', ',')} %',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == kPrimaryMouseButton) widget.onPointerDown();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onContextMenu == null
                ? null
                : (details) => widget.onContextMenu!(details.globalPosition),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: _hovered ? 1 : .82),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.selected
                      ? accent
                      : Colors.black.withValues(alpha: .15),
                  width: widget.selected ? 3 : 1,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => _label(constraints),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BoxConstraints constraints) {
    if (constraints.maxWidth < 48 || constraints.maxHeight < 22) {
      return const SizedBox.expand();
    }
    const style = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      shadows: [Shadow(blurRadius: 3, color: Color(0xCC000000))],
    );
    final entry = widget.entry;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (entry.isDirectory && constraints.maxWidth > 70) ...[
                  const Icon(
                    Icons.folder_rounded,
                    size: 14,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 3, color: Color(0xCC000000))],
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
              ],
            ),
            if (constraints.maxHeight >= 42)
              Text(
                formatExplorerSize(widget.bytes),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(fontWeight: FontWeight.w400),
              ),
          ],
        ),
      ),
    );
  }
}
